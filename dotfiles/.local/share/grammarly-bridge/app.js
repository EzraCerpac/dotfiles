const textarea = document.querySelector("#draft");
const status = document.querySelector("#status");
const token = location.hash.slice(1);

async function loadDraft() {
  if (!/^[a-f0-9]{64}$/.test(token)) {
    throw new Error("Open this page from :GrammarlyBridge in Neovim.");
  }

  const response = await fetch("/api/draft", {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(`Draft unavailable (${response.status}). Restart :GrammarlyBridge.`);
  }

  textarea.value = await response.text();
  textarea.disabled = false;
  textarea.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText" }));
  textarea.focus();
  status.textContent = "Draft ready. Grammarly may now check this textarea.";
}

loadDraft().catch((error) => {
  status.textContent = error instanceof Error ? error.message : String(error);
  status.classList.add("error");
});
