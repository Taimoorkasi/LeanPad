// Crops the shots LeanPad Shots took in game into docs/images, where the README and CurseForge page point.
// Reads each shot's name, time and frame rectangle from the tool's saved variables, finds the screenshot WoW wrote
// within a few seconds of that time, crops it to the frame with a margin and saves it as a PNG.
// The WoW folder defaults to the standard install; set WOW_RETAIL to another _retail_ folder if yours differs.
const fs = require("fs");
const path = require("path");
const { Jimp } = require("jimp");

const RETAIL = process.env.WOW_RETAIL || "C:/Program Files (x86)/World of Warcraft/_retail_";
const OUT = path.join(__dirname, "..", "docs", "images");
const MARGIN = 16; // pixels around the frame
const NEAR = 10; // seconds a screenshot's file time may differ from the shot's
// Each shot's file in docs/images; the settings shot keeps the name the docs already use.
const FILES = {
	"settings-controls": "easy-to-understand-settings.png",
	"settings-dialogue": "settings-dialogue.png",
	"dialogue-preview": "dialogue-preview.png",
	"dialogue-npc": "dialogue-npc.png",
	"dialogue-quest": "dialogue-quest.png",
	"dialogue-rewards": "dialogue-rewards.png",
	popup: "popup.png",
};

// The newest LeanPadShots.lua among the accounts' saved variables.
function savedVariables() {
	const accounts = path.join(RETAIL, "WTF", "Account");
	const found = fs.readdirSync(accounts)
		.map((account) => path.join(accounts, account, "SavedVariables", "LeanPadShots.lua"))
		.filter((file) => fs.existsSync(file))
		.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
	if (!found.length) throw new Error("No LeanPadShots.lua yet: take shots with /lpshots, then /reload so WoW saves them.");
	return found[0];
}

// Shots as { name, time, left, top, right, bottom }, from the "name|time|left|top|right|bottom" strings in the text.
function shots(text) {
	const pattern = /"([\w-]+)\|(\d+)\|(-?\d+)\|(-?\d+)\|(-?\d+)\|(-?\d+)"/g;
	return [...text.matchAll(pattern)].map((m) => ({
		name: m[1], time: Number(m[2]), left: Number(m[3]), top: Number(m[4]), right: Number(m[5]), bottom: Number(m[6]),
	}));
}

// The first screenshot written after the shot, if one is near enough. The game's time() drops the fraction, so the
// file always comes after the shot's second, and the shot before it can sit closer in absolute terms.
function screenshotFor(shot, screenshots) {
	let best;
	for (const file of screenshots) {
		const gap = file.time - shot.time;
		if (gap >= 0 && gap <= NEAR && (!best || gap < best.gap)) best = { ...file, gap };
	}
	return best && best.path;
}

// The frame's rectangle with the margin, kept inside the image.
function crop(shot, width, height) {
	const x = Math.max(0, shot.left - MARGIN), y = Math.max(0, shot.top - MARGIN);
	const w = Math.min(width, shot.right + MARGIN) - x, h = Math.min(height, shot.bottom + MARGIN) - y;
	return { x, y, w, h };
}

async function main() {
	const dir = path.join(RETAIL, "Screenshots");
	const screenshots = fs.readdirSync(dir)
		.filter((name) => /\.(jpe?g|png|tga)$/i.test(name))
		.map((name) => ({ path: path.join(dir, name), time: fs.statSync(path.join(dir, name)).mtimeMs / 1000 }));
	let saved = 0;
	for (const shot of shots(fs.readFileSync(savedVariables(), "utf8"))) {
		const file = screenshotFor(shot, screenshots), out = FILES[shot.name];
		if (!out) continue;
		if (!file) {
			console.log(`skipped ${shot.name}: no screenshot within ${NEAR}s of when it was taken`);
			continue;
		}
		const image = await Jimp.read(file);
		image.crop(crop(shot, image.bitmap.width, image.bitmap.height));
		await image.write(path.join(OUT, out));
		console.log(`${shot.name} -> docs/images/${out}`);
		saved++;
	}
	console.log(`${saved} image(s) saved.`);
}

module.exports = { shots, screenshotFor, crop };
if (require.main === module) main().catch((error) => {
	console.error(error.message);
	process.exit(1);
});
