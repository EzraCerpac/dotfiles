// Automatically enable Vim keybindings in Pluto using MutationObserver
// This version is lightweight and responds instantly when new cells are added.

window.addEventListener("DOMContentLoaded", () => {
    // Load CodeMirror's Vim keymap if not already loaded
    if (!window.CodeMirror?.keyMap?.vim) {
        const script = document.createElement("script");
        script.src = "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.5/keymap/vim.min.js";
        script.onload = () => console.log("[Pluto Vim] Vim keymap loaded");
        document.head.appendChild(script);
    }

    // Function to enable Vim mode in all CodeMirror instances
    const enableVim = () => {
        document.querySelectorAll(".CodeMirror").forEach(cmEl => {
            const cm = cmEl.CodeMirror;
            if (cm && cm.getOption("keyMap") !== "vim") {
                cm.setOption("keyMap", "vim");
                cm.setOption("showCursorWhenSelecting", true);
                console.log("[Pluto Vim] Enabled Vim mode for cell");
            }
        });
    };

    // Observe the notebook DOM for new cells
    const observer = new MutationObserver(mutations => {
        for (const mutation of mutations) {
            if (mutation.addedNodes.length > 0) enableVim();
        }
    });

    observer.observe(document.body, { childList: true, subtree: true });

    // Initial activation
    enableVim();

    console.log("[Pluto Vim] Auto-enable Vim mode active.");
});

