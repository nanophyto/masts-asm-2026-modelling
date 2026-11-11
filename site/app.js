"use strict";

const stationList = document.getElementById("station-list");
const searchField = document.getElementById("station-search");
const message = document.getElementById("station-message");
const availability = document.getElementById("availability");
let accounts = [];

const monitorIcon = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><rect x="3" y="4" width="18" height="14" rx="2"/><path d="M8 21h8M12 18v3"/></svg>`;

function validLink(url) {
  if (typeof url !== "string") return false;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" &&
      parsed.username === "" && parsed.password === "" &&
      parsed.hostname.endsWith(".cloudworkstations.dev");
  } catch (_) { return false; }
}

function normalize(text) {
  return String(text).toLowerCase().replace(/@nanophyto\.org$/, "").replace(/[^a-z0-9]/g, "");
}

function accountCard(account) {
  const ready = validLink(account.url);
  const card = document.createElement("article");
  card.className = `station-card${ready ? " ready" : ""}`;
  const heading = document.createElement("div");
  heading.className = "station-card-heading";
  const label = document.createElement("span");
  label.className = "station-name";
  label.textContent = account.name;
  const icon = document.createElement("span");
  icon.className = "station-icon";
  icon.innerHTML = monitorIcon;
  heading.append(label, icon);
  const username = document.createElement("span");
  username.className = "station-username";
  username.textContent = `${account.username}@nanophyto.org`;
  const footer = document.createElement("div");
  footer.className = `station-status${ready ? "" : " not-ready"}`;
  if (ready) {
    const link = document.createElement("a");
    link.className = "station-action";
    link.href = account.url;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.setAttribute("aria-label", `Open ${account.name}'s workstation`);
    link.textContent = "Open workstation";
    const arrow = document.createElement("span");
    arrow.className = "station-arrow";
    arrow.setAttribute("aria-hidden", "true");
    arrow.textContent = "↗";
    link.append(arrow);
    footer.append(link);
  } else {
    footer.textContent = "Link coming soon";
  }
  card.append(heading, username, footer);
  return card;
}

function render() {
  const search = normalize(searchField.value.trim());
  const selected = search
    ? accounts.filter(a => normalize(a.name).includes(search) || a.username.includes(search))
    : accounts;
  stationList.replaceChildren(...selected.map(accountCard));
  message.textContent = search && !selected.length
    ? "No matching account. Check the name on your @nanophyto.org sign-in."
    : search ? `${selected.length} matching account${selected.length === 1 ? "" : "s"}` : "";
}

async function loadStations() {
  try {
    const response = await fetch(`./workstations.json?v=${Date.now()}`, {cache: "no-store"});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const config = await response.json();
    if (config.schemaVersion !== 2 || !Array.isArray(config.accounts) || config.accounts.length !== 28 ||
        config.accounts.some(a => !/^[a-z0-9]+$/.test(a.username) || !a.name || a.username === "admin")) {
      throw new Error("Unexpected account configuration");
    }
    accounts = config.accounts;
    const configured = accounts.filter(a => validLink(a.url)).length;
    availability.textContent = `${configured} / ${accounts.length} links configured`;
    availability.classList.toggle("waiting", configured === 0);
    const params = new URLSearchParams(location.search);
    const chosen = params.get("account");
    if (chosen && accounts.some(a => a.username === normalize(chosen))) {
      searchField.value = chosen;
    }
    render();
  } catch (error) {
    availability.textContent = "Links unavailable";
    availability.classList.add("waiting");
    message.textContent = "Unable to load workstation links. Please refresh the page or ask an organiser.";
    console.error("Cannot load workstation configuration:", error);
  }
}

searchField.addEventListener("input", render);
loadStations();
