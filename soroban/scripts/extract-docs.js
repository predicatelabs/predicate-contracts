#!/usr/bin/env node
/**
 * extract-docs.js
 *
 * Reads a Soroban contract spec JSON (as produced by
 * `stellar contract info interface --wasm <wasm> --output json-formatted`)
 * and emits a structured docs file the consuming app can render without
 * parsing Markdown at runtime.
 *
 * Output shape:
 *
 *   {
 *     "<fn_name>": {
 *       "summary": "First paragraph of the docstring.",
 *       "args": [{ "name": "admin", "description": "..." }],
 *       "errors": [{ "description": "Reverts if ..." }],
 *       "events": [{ "description": "Emits ..." }]
 *     },
 *     ...
 *   }
 *
 * Conventions expected in source docstrings (enforced by convention, not
 * by this script):
 *
 *   - `# Arguments`, `# Errors`, `# Events` as section headers
 *   - Bullets formatted as `* `name` - description` (backtick-wrapped name)
 *   - Continuation lines indented with 2 spaces
 */

"use strict";

const fs = require("node:fs");

function usage() {
    console.error("usage: extract-docs.js <contractspec.json> <out.docs.json>");
    process.exit(2);
}

function readEntries(rawText) {
    const trimmed = rawText.trim();
    if (!trimmed) return [];

    try {
        const parsed = JSON.parse(trimmed);
        return Array.isArray(parsed) ? parsed : [parsed];
    } catch (_) {
        return trimmed
            .split("\n")
            .map((line) => line.trim())
            .filter(Boolean)
            .map((line) => JSON.parse(line));
    }
}

const SECTION_HEADERS = {
    "# Arguments": "args",
    "# Errors": "errors",
    "# Events": "events",
};

function parseDoc(doc) {
    if (!doc || typeof doc !== "string") return null;

    const lines = doc.replace(/\r\n/g, "\n").split("\n");
    const result = { summary: "", args: [], errors: [], events: [] };
    const summaryLines = [];

    let section = "summary";
    let currentBullet = null;

    const flush = () => {
        if (!currentBullet) return;
        if (section === "args" || section === "errors" || section === "events") {
            result[section].push(currentBullet);
        }
        currentBullet = null;
    };

    for (const rawLine of lines) {
        const trimmed = rawLine.trim();
        const headerKey = SECTION_HEADERS[trimmed];

        if (headerKey) {
            flush();
            section = headerKey;
            continue;
        }
        if (trimmed.startsWith("# ")) {
            flush();
            section = "other";
            continue;
        }

        if (section === "summary") {
            if (trimmed) summaryLines.push(trimmed);
            continue;
        }
        if (section === "other") continue;

        const namedBullet = trimmed.match(/^[*-]\s+`([^`]+)`\s*-\s*(.*)$/);
        if (namedBullet) {
            flush();
            currentBullet = { name: namedBullet[1], description: namedBullet[2].trim() };
            continue;
        }

        const plainBullet = trimmed.match(/^[*-]\s+(.*)$/);
        if (plainBullet) {
            flush();
            currentBullet = { description: plainBullet[1].trim() };
            continue;
        }

        if (currentBullet && trimmed) {
            currentBullet.description = `${currentBullet.description} ${trimmed}`.trim();
        }
    }
    flush();

    result.summary = summaryLines.join(" ").trim();

    const hasContent =
        result.summary || result.args.length || result.errors.length || result.events.length;
    return hasContent ? result : null;
}

function main() {
    const [, , inFile, outFile] = process.argv;
    if (!inFile || !outFile) usage();

    const entries = readEntries(fs.readFileSync(inFile, "utf8"));
    const docs = {};

    for (const entry of entries) {
        const fn = entry && entry.function_v0;
        if (!fn || typeof fn.name !== "string") continue;

        const parsed = parseDoc(fn.doc);
        if (parsed) docs[fn.name] = parsed;
    }

    fs.writeFileSync(outFile, `${JSON.stringify(docs, null, 2)}\n`);
    console.log(`Wrote ${Object.keys(docs).length} function doc entries to ${outFile}`);
}

main();
