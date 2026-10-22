// Draws LeanPad's controller art: steel line art on a slate body, the editor's own palette.
// Writes LeanPad/Art/*.tga (32-bit, power-of-two sizes, as the client wants) and an SVG + PNG preview of each pad.
// Button positions here are mirrored in ns.PADS in LeanPad/Controller.lua; change both together.
// Proportions were taken from the CC0 "8th gen console vector gamepad collection" by TheHoodieGuy02;
// every path is drawn fresh.
//   cd tools && npm install && node draw-pads.js
const fs = require("fs");
const path = require("path");
const { Resvg } = require("@resvg/resvg-js");

const OUT = path.join(__dirname, "..", "LeanPad", "Art");
const PREVIEW = path.join(__dirname, "preview");
const C = 1024; // symmetry axis
const INK = "#8fa6bd", INK_SOFT = "#4f6377", BODY = "#151b24", CORE = "#0e1218", PART = "#111720";
const GLYPH = { tri: "#3ccfa4", sq: "#e58ad8", cir: "#ff7a7a", x: "#8fb2ff", a: "#6fcf6f", b: "#f06a6a", xb: "#6f9cff", y: "#f2cf3a" };

// Mirrors a left-half outline (from the axis at the top to the axis at the bottom) into one closed path.
// Each segment is [x1,y1,x2,y2,x,y] (cubic) or [x,y] (line), absolute.
function mirrored(start, segs) {
	const pts = [start];
	let d = `M${start[0]} ${start[1]}`;
	for (const s of segs) {
		d += s.length === 6 ? ` C${s.join(" ")}` : ` L${s.join(" ")}`;
		pts.push(s.slice(-2));
	}
	const mx = (x) => 2 * C - x;
	for (let i = segs.length - 1; i >= 0; i--) {
		const s = segs[i], from = pts[i];
		d += s.length === 6
			? ` C${mx(s[2])} ${s[3]} ${mx(s[0])} ${s[1]} ${mx(from[0])} ${from[1]}`
			: ` L${mx(from[0])} ${from[1]}`;
	}
	return d + " Z";
}
const mirrorX = (x) => 2 * C - x;
const el = (tag, attrs, inner = "") =>
	`<${tag} ${Object.entries(attrs).map(([k, v]) => `${k}="${v}"`).join(" ")}${inner ? `>${inner}</${tag}>` : "/>"}`;

function shoulders(lx, ly, w, h, trigger) {
	const shapes = [];
	for (const flip of [false, true]) {
		const x = flip ? mirrorX(lx + w) : lx;
		shapes.push(el("rect", { x: flip ? x + 30 : x, y: ly - trigger, width: w - 30, height: h, rx: h / 2, fill: CORE, stroke: INK_SOFT, "stroke-width": 5 }));
		shapes.push(el("rect", { x, y: ly, width: w, height: h * 0.8, rx: h * 0.4, fill: PART, stroke: INK, "stroke-width": 6 }));
	}
	return shapes.join("");
}

function stick(cx, cy) {
	return [
		el("circle", { cx, cy, r: 112, fill: CORE, stroke: INK_SOFT, "stroke-width": 5 }),
		el("circle", { cx, cy, r: 78, fill: PART, stroke: INK, "stroke-width": 6 }),
		el("circle", { cx, cy, r: 52, fill: "none", stroke: INK_SOFT, "stroke-width": 4, "stroke-dasharray": "6 10" }),
	].join("");
}

// Four arrow-tipped arms around (cx, cy) that stop short of the centre, leaving a clear gap.
function dpad(cx, cy, reach, width) {
	const w = width / 2, base = 50, point = 26;
	const d = `M${cx - w} ${cy - base} L${cx - w} ${cy - reach + 12} Q${cx - w} ${cy - reach} ${cx - w + 12} ${cy - reach} L${cx + w - 12} ${cy - reach} Q${cx + w} ${cy - reach} ${cx + w} ${cy - reach + 12} L${cx + w} ${cy - base} L${cx} ${cy - point} Z`;
	return [0, 90, 180, 270].map((rot) =>
		el("path", { d, transform: `rotate(${rot} ${cx} ${cy})`, fill: PART, stroke: INK, "stroke-width": 6, "stroke-linejoin": "round" })).join("");
}

function faceButton(cx, cy, glyph, r) {
	const g = GLYPH[glyph], s = 30;
	let mark;
	if (glyph === "tri") mark = el("path", { d: `M${cx} ${cy - s} L${cx + s * 0.95} ${cy + s * 0.65} L${cx - s * 0.95} ${cy + s * 0.65} Z`, fill: "none", stroke: g, "stroke-width": 7, "stroke-linejoin": "round" });
	else if (glyph === "sq") mark = el("rect", { x: cx - s * 0.8, y: cy - s * 0.8, width: s * 1.6, height: s * 1.6, fill: "none", stroke: g, "stroke-width": 7 });
	else if (glyph === "cir") mark = el("circle", { cx, cy, r: s * 0.85, fill: "none", stroke: g, "stroke-width": 7 });
	else if (glyph === "x") mark = el("path", { d: `M${cx - s * 0.8} ${cy - s * 0.8} L${cx + s * 0.8} ${cy + s * 0.8} M${cx + s * 0.8} ${cy - s * 0.8} L${cx - s * 0.8} ${cy + s * 0.8}`, stroke: g, "stroke-width": 7, "stroke-linecap": "round" });
	else mark = el("text", { x: cx, y: cy + 20, "text-anchor": "middle", "font-family": "Arial, sans-serif", "font-weight": 700, "font-size": 58, fill: g }, glyph === "xb" ? "X" : glyph.toUpperCase());
	return el("circle", { cx, cy, r, fill: PART, stroke: INK, "stroke-width": 6 }) + mark;
}

const pill = (cx, cy, w, h) => el("rect", { x: cx - w / 2, y: cy - h / 2, width: w, height: h, rx: Math.min(w, h) / 2, fill: PART, stroke: INK, "stroke-width": 5 });
const svg = (viewBox, body, size = "") => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}"${size}>${body}</svg>\n`;

const pads = {
	PadPlayStation: {
		viewBox: "150 420 1748 1200",
		body: () => [
			shoulders(392, 512, 240, 56, 34),
			el("path", { d: mirrored([C, 560], [
				[700, 560], [655, 560, 640, 528, 600, 520], [520, 500, 418, 506, 366, 566], [296, 646, 260, 770, 244, 912],
				[226, 1070, 206, 1270, 214, 1410], [222, 1512, 276, 1584, 350, 1584], [424, 1584, 480, 1508, 548, 1386],
				[592, 1308, 640, 1284, 716, 1290], [820, 1300, 912, 1270, C, 1270],
			]), fill: BODY, stroke: INK, "stroke-width": 8, "stroke-linejoin": "round" }),
			el("path", { d: mirrored([C, 572], [
				[760, 572], [728, 572, 712, 596, 708, 630], [700, 760, 690, 880, 660, 980], [630, 1080, 640, 1200, 720, 1250], [800, 1296, 900, 1262, C, 1262],
			]), fill: CORE, stroke: INK_SOFT, "stroke-width": 4, "stroke-linejoin": "round" }),
			el("rect", { x: 772, y: 596, width: 504, height: 300, rx: 44, fill: PART, stroke: INK, "stroke-width": 6 }),
			el("path", { d: "M748 640 L742 860 M1300 640 L1306 860", fill: "none", stroke: "#f6b73c", "stroke-width": 5, "stroke-linecap": "round", opacity: 0.6 }),
			pill(712, 650, 30, 62), pill(mirrorX(712), 650, 30, 62),
			dpad(468, 830, 130, 80),
			faceButton(1580, 708, "tri", 56), faceButton(1458, 830, "sq", 56), faceButton(1702, 830, "cir", 56), faceButton(1580, 952, "x", 56),
			stick(772, 1112), stick(mirrorX(772), 1112),
			el("circle", { cx: C, cy: 1108, r: 34, fill: PART, stroke: INK, "stroke-width": 5 }),
			pill(C, 1184, 64, 20),
		].join(""),
	},
	PadXbox: {
		viewBox: "200 470 1648 1150",
		body: () => [
			shoulders(420, 574, 230, 52, 30),
			el("path", { d: mirrored([C, 600], [
				[820, 600], [760, 600, 700, 560, 610, 566], [520, 572, 440, 590, 404, 640], [370, 690, 350, 760, 330, 840],
				[290, 1000, 250, 1180, 246, 1350], [244, 1470, 300, 1560, 380, 1572], [450, 1580, 520, 1500, 600, 1380],
				[640, 1320, 690, 1300, 760, 1300], [860, 1300, 940, 1300, C, 1300],
			]), fill: BODY, stroke: INK, "stroke-width": 8, "stroke-linejoin": "round" }),
			el("circle", { cx: C, cy: 700, r: 52, fill: PART, stroke: INK, "stroke-width": 6 }),
			pill(900, 830, 52, 52), pill(1148, 830, 52, 52),
			el("path", { d: "M884 822 h18 v-10 h14 v18 h-10 M1134 818 h28 M1134 830 h28 M1134 842 h28", fill: "none", stroke: INK, "stroke-width": 4, "stroke-linecap": "round" }),
			stick(640, 830), dpad(830, 1090, 104, 70), stick(1218, 1090),
			faceButton(1410, 720, "y", 50), faceButton(1300, 830, "xb", 50), faceButton(1520, 830, "b", 50), faceButton(1410, 940, "a", 50),
		].join(""),
	},
};

// White strokes, tinted in game with SetVertexColor.
const rings = {
	Ring: el("circle", { cx: 64, cy: 64, r: 58, fill: "none", stroke: "#fff", "stroke-width": 7 }),
	RingSquare: el("rect", { x: 6, y: 6, width: 116, height: 116, rx: 26, fill: "none", stroke: "#fff", "stroke-width": 7 }),
};

// Uncompressed 32-bit TGA, top-left origin. resvg's pixels are premultiplied RGBA; TGA wants straight BGRA.
function writeTga(file, width, height, rgba) {
	const header = Buffer.alloc(18);
	header[2] = 2;
	header.writeUInt16LE(width, 12);
	header.writeUInt16LE(height, 14);
	header[16] = 32;
	header[17] = 0x28;
	const body = Buffer.alloc(width * height * 4);
	for (let i = 0; i < rgba.length; i += 4) {
		const a = rgba[i + 3];
		const un = (c) => (a ? Math.min(255, Math.round((c * 255) / a)) : 0);
		body[i] = un(rgba[i + 2]);
		body[i + 1] = un(rgba[i + 1]);
		body[i + 2] = un(rgba[i]);
		body[i + 3] = a;
	}
	fs.writeFileSync(file, Buffer.concat([header, body]));
}

function render(name, text, width, height) {
	const image = new Resvg(text, { fitTo: { mode: "width", value: width }, font: { loadSystemFonts: true } }).render();
	if (image.width !== width || image.height !== height) throw new Error(`${name}: rendered ${image.width}x${image.height}`);
	writeTga(path.join(OUT, name + ".tga"), width, height, image.pixels);
	return image;
}

fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(PREVIEW, { recursive: true });
for (const [name, pad] of Object.entries(pads)) {
	const body = pad.body();
	// 1024x512 canvas; the drawing is centred at full height, so the game crops it with SetTexCoord.
	render(name, svg(pad.viewBox, body, ' width="1024" height="512" preserveAspectRatio="xMidYMid meet"'), 1024, 512);
	fs.writeFileSync(path.join(PREVIEW, name + ".svg"), svg(pad.viewBox, body));
	const png = new Resvg(svg(pad.viewBox, body), { fitTo: { mode: "width", value: 900 }, background: "#10151c", font: { loadSystemFonts: true } }).render().asPng();
	fs.writeFileSync(path.join(PREVIEW, name + ".png"), png);
}
for (const [name, shape] of Object.entries(rings)) render(name, svg("0 0 128 128", shape), 128, 128);
console.log("wrote", fs.readdirSync(OUT).join(", "));
