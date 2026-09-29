// Bakes models to GLB with wow.export's own exporters (MIT; cloned into
// .cache/wow.export by setup.sh): each WMO or M2 once, textures
// inside, into .cache/scene/models/<file id>.glb.
//
//   node Tools/ClientMap/scene/models.js <file id> ...     (serve.py must be running)
//
// The exporters are wow.export's; only the desktop app round them is swapped
// for stand-ins here: its state (core), log, constants and listfile. Game
// files come from serve.py (/file/<id>), which also finds the textures the
// Forever beta does not keep on disk.
'use strict';
const fs = require('fs');
const path = require('path');
const Module = require('module');

const HERE = __dirname;
const CACHE = path.resolve(HERE, '..', '.cache');
const WOWEXPORT = path.join(CACHE, 'wow.export', 'src', 'js');
const OUT = path.join(CACHE, 'scene', 'models');
const SERVER = process.env.OPENROAD_SERVER || 'http://127.0.0.1:8765';

// --- Stand-ins for the desktop app ----------------------------------------------------

// The GLB writer names its generator from the app's manifest.
global.nw = { App: { manifest: { name: 'nuuroad', version: '1' } }, Shell: { openItem() {} } };

let BufferWrapper = null;
const casc = {
	async getFile(id) {
		const response = await fetch(SERVER + '/file/' + id);
		if (!response.ok)
			throw new Error('file ' + id + ' not in the store');
		return BufferWrapper.from(Buffer.from(await response.arrayBuffer()));
	},
	async getFileByName(name) {
		const id = listfile.getByFilename(name);
		if (!id)
			throw new Error('no file named ' + name);
		return casc.getFile(id);
	},
};
casc.getVirtualFileByID = casc.getFile;
casc.getVirtualFileByName = casc.getFileByName;

const core = {
	view: {
		casc, isBusy: 0, exportCancelled: false,
		config: {
			exportDirectory: OUT, overwriteFiles: true, pathFormat: 'posix', removePathSpaces: false,
			enableSharedChildren: false, enableAbsoluteGLTFPaths: false, enableAbsoluteCSVPaths: false,
			modelsExportUV2: false, modelsExportCollision: false, modelsExportAnimations: false,
			modelsExportWithBonePrefix: false, exportM2Bones: false, exportM2Meta: false, exportWMOMeta: false,
			exportTextureAlpha: true, modelsExportTextures: true,
		},
	},
	events: { on() {}, emit() {}, once() {} },
	setToast() {}, hideToast() {},
};

const log = { write: (...args) => { if (process.env.OPENROAD_VERBOSE) console.log(require('util').format(...args)); }, timeLog() {}, timeEnd() {} };

const constants = {
	VERSION: 'nuuroad', SHADER_PATH: '', DATA_PATH: CACHE,
	GAME: { MAP_SIZE: 64, MAP_SIZE_SQ: 4096, MAP_COORD_BASE: 51200 / 3, TILE_SIZE: (51200 / 3) / 32, MAP_OFFSET: 17066 },
	MAGIC: { M3DT: 0x5444334D, MD21: 0x3132444D, MD20: 0x3032444D },
	EXPORT: { DEFAULT_PATH: OUT },
};

// The community listfile, both ways, read once.
const byName = new Map(), byId = new Map();
function loadListfile() {
	const text = fs.readFileSync(path.join(CACHE, 'listfile.csv'), 'utf8');
	let start = 0;
	while (start < text.length) {
		let end = text.indexOf('\n', start);
		if (end < 0) end = text.length;
		const semi = text.indexOf(';', start);
		if (semi > start && semi < end) {
			const id = +text.slice(start, semi), name = text.slice(semi + 1, end).trim().toLowerCase();
			byName.set(name, id); byId.set(id, name);
		}
		start = end + 1;
	}
}
const listfile = {
	getByFilename: name => byName.get(String(name).toLowerCase().replace(/\\/g, '/')),
	getByID: id => byId.get(id),
	getByIDOrUnknown: (id, ext = '') => byId.get(id) || ('unknown/' + id + ext),
	existsByID: id => byId.has(id),
	isLoaded: () => true,
	stripFileEntry: s => s, formatUnknownFile: s => s,
};

const swapped = {
	[path.join(WOWEXPORT, 'core.js')]: core,
	[path.join(WOWEXPORT, 'log.js')]: log,
	[path.join(WOWEXPORT, 'constants.js')]: constants,
	[path.join(WOWEXPORT, 'casc', 'listfile.js')]: listfile,
};
const resolve = Module._resolveFilename;
Module._resolveFilename = function (request, parent, ...rest) {
	if (request === 'webp-wasm')
		return 'nuuroad:webp';
	return resolve.call(this, request, parent, ...rest);
};
const load = Module._load;
Module._load = function (request, parent, ...rest) {
	if (request === 'webp-wasm')
		return {};
	const file = Module._resolveFilename(request, parent, ...rest);
	if (swapped[file])
		return swapped[file];
	return load.call(this, request, parent, ...rest);
};

// --- Baking ---------------------------------------------------------------------------------

class Helper {
	// The progress reporter the exporters talk to.
	setCurrentTaskName() {} setCurrentTaskValue() {} setCurrentTaskMax() {} isCancelled() { return false; }
	mark() {} start() {} finish() {}
}

async function bake(id) {
	const name = listfile.getByID(id) || '';
	const out = path.join(OUT, id + '.glb');
	const data = await casc.getFile(id);
	if (name.endsWith('.wmo')) {
		const WMOExporter = require(path.join(WOWEXPORT, '3D', 'exporters', 'WMOExporter'));
		const exporter = new WMOExporter(data, id);
		await exporter.exportAsGLTF(out, new Helper(), 'glb');
	} else {
		const M2Exporter = require(path.join(WOWEXPORT, '3D', 'exporters', 'M2Exporter'));
		const exporter = new M2Exporter(data, undefined, id);
		await exporter.exportAsGLTF(out, new Helper(), 'glb');
	}
	return out;
}

async function main() {
	const ids = process.argv.slice(2).map(Number).filter(Boolean);
	fs.mkdirSync(OUT, { recursive: true });
	loadListfile();
	BufferWrapper = require(path.join(WOWEXPORT, 'buffer'));
	let done = 0, failed = 0;
	for (const id of ids) {
		const t0 = Date.now();
		try {
			const out = await bake(id);
			const size = fs.existsSync(out) ? fs.statSync(out).size : 0;
			if (!size) throw new Error('nothing written');
			console.log(`ok ${id} ${listfile.getByID(id) || ''} ${(size / 1024).toFixed(0)} KB ${Date.now() - t0} ms`);
			done++;
		} catch (e) {
			console.log(`failed ${id} ${listfile.getByID(id) || ''}: ${e.message}`);
			failed++;
		}
	}
	console.log(`${done} baked, ${failed} failed`);
}

main();
