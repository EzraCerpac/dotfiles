// Automatically enable Vim keybindings in Pluto — safe version that waits for CodeMirror.

(function waitForCodeMirror() {
    if (!window.CodeMirror) {
        console.log("[Pluto Vim] Waiting for CodeMirror...");
        return setTimeout(waitForCodeMirror, 500);
    }

    console.log("[Pluto Vim] CodeMirror detected, loading Vim mode...");

    // Load CodeMirror's Vim keymap
    if (!window.CodeMirror.keyMap?.vim) {
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

    // Observe notebook DOM for new cells
    const observer = new MutationObserver(() => enableVim());
    observer.observe(document.body, { childList: true, subtree: true });

    // Enable immediately for any existing cells
    enableVim();

    console.log("[Pluto Vim] Vim mode auto-enable active.");
})();

