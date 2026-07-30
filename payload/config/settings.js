/**
 * Node-RED settings for the MEO 3 gateway.
 *
 * Installed to /etc/meo-3/settings.js and passed with `red.js -s`. Branding goes
 * through editorTheme (see node-red-meo/docs/editor-ui-customization.md) so
 * upstream merges stay clean.
 */

const path = require("path");

// Overridable so the bundle also works extracted-and-run-in-place.
const DATA_DIR = process.env.MEO_NODE_RED_DIR || "/var/lib/meo-3/node-red";

// One settings.js serves both the .deb (/usr/share) and the tarball (in-tree),
// so resolve branding instead of hardcoding a prefix.
const BRANDING = [
    process.env.MEO_BRANDING_DIR,
    "/usr/share/meo-3/branding",
    path.join(__dirname, "branding")
].filter(Boolean).find((p) => require("fs").existsSync(p)) || "";

module.exports = {
    uiPort: process.env.PORT || 1880,
    userDir: DATA_DIR,
    flowFile: "flows.json",
    // Flows are edited by teachers, not read by machines — keep them diffable.
    flowFilePretty: true,

    // Gateway-local install; MEO nodes ship inside the fork so nothing to add here.
    nodesDir: path.join(DATA_DIR, "nodes"),

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    editorTheme: {
        page: {
            title: "MEO 3",
            ...(BRANDING && { favicon: path.join(BRANDING, "meo-3-logo.png") })
        },
        header: {
            title: "MEO 3",
            ...(BRANDING && { image: path.join(BRANDING, "meo-3-logo_compact.png") })
        },
        projects: {
            // Classroom gateways don't want the git-projects workflow.
            enabled: false
        }
    },

    functionGlobalContext: {},
    exportGlobalContextKeys: false
};
