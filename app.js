const FLAG = code => `https://api.fifa.com/api/v3/picture/flags-sq-2/${code}`;
const CONFEDS = ['All', 'UEFA', 'CONMEBOL', 'CONCACAF', 'CAF', 'AFC', 'OFC'];

const state = { data: null, confed: 'All', query: '', open: null };
const $ = id => document.getElementById(id);

const esc = s => String(s).replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
const fmtDate = iso => new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const signed = (n, digits = 2) => (n > 0 ? '+' : '') + n.toFixed(digits);
const tone = n => (n > 0 ? 'up' : n < 0 ? 'down' : 'flat');

function flag(code) {
  return `<img class="flag" src="${FLAG(code)}" alt="" loading="lazy" onerror="this.style.visibility='hidden'">`;
}

function moveBadge(n) {
  if (!n) return '<span class="move flat">–</span>';
  return `<span class="move ${tone(n)}">${n > 0 ? '▲' : '▼'}${Math.abs(n)}</span>`;
}

function renderMeta({ official, generatedAt, matches, matchesSince }) {
  const items = [
    ['Official ranking', fmtDate(official.pubDate)],
    ['Matches applied', `${matches.length} since ${fmtDate(matchesSince)}`],
    ['Last refreshed', new Date(generatedAt).toLocaleString()],
  ];
  if (official.nextPubDate) items.push(['Next official release', fmtDate(official.nextPubDate)]);
  $('meta').innerHTML = items.map(([k, v]) => `<div><dt>${k}</dt><dd>${esc(v)}</dd></div>`).join('');
}

function renderMovers(teams) {
  const byPts = [...teams].sort((a, b) => b.pointsChange - a.pointsChange);
  const byRank = [...teams].sort((a, b) => b.rankChange - a.rankChange);
  const cards = [
    ['No. 1', teams[0], `${teams[0].livePoints.toFixed(2)}`],
    ['Biggest gain', byPts[0], signed(byPts[0].pointsChange)],
    ['Biggest drop', byPts.at(-1), signed(byPts.at(-1).pointsChange)],
    ['Most places up', byRank[0], `▲${byRank[0].rankChange}`],
  ];
  $('movers').innerHTML = cards.map(([label, t, value]) => `
    <div class="mover">
      <div class="label">${label}</div>
      <div class="team">${flag(t.code)}${esc(t.name)}</div>
      <div class="value">${esc(value)}</div>
    </div>`).join('');
}

function renderTabs() {
  $('confeds').innerHTML = CONFEDS.map(c =>
    `<button role="tab" aria-selected="${c === state.confed}" data-confed="${c}">${c}</button>`).join('');
}

function teamMatches(code) {
  return state.data.matches.filter(m => m.home === code || m.away === code);
}

function detailRow(t) {
  const ms = teamMatches(t.code);
  const body = ms.length
    ? `<ul>${ms.map(m => {
        const d = m.home === t.code ? m.homeDelta : m.awayDelta;
        return `<li>${esc(m.date)} · ${esc(m.home)} ${esc(m.score)} ${esc(m.away)} · ${esc(m.tournament)} (I=${m.importance}) · <span class="${tone(d)}">${signed(d)}</span></li>`;
      }).join('')}</ul>`
    : 'No matches since the last official ranking.';
  return `<tr class="detail"><td colspan="5">${body}</td></tr>`;
}

function renderTable() {
  const q = state.query.trim().toLowerCase();
  const teams = state.data.teams.filter(t =>
    (state.confed === 'All' || t.confed === state.confed) &&
    (!q || t.name.toLowerCase().includes(q) || t.code.toLowerCase().includes(q)));

  $('rows').innerHTML = teams.map(t => `
    <tr data-code="${t.code}" aria-expanded="${state.open === t.code}">
      <td class="num rank">${t.liveRank}${moveBadge(t.rankChange)}</td>
      <td class="num official hide-sm">${t.officialRank}</td>
      <td><div class="team-cell">${flag(t.code)}<span>${esc(t.name)} <small>${t.confed}</small></span></div></td>
      <td class="num">${t.livePoints.toFixed(2)}</td>
      <td class="num ${tone(t.pointsChange)}">${t.pointsChange ? signed(t.pointsChange) : '–'}</td>
    </tr>${state.open === t.code ? detailRow(t) : ''}`).join('');
  $('empty').hidden = teams.length > 0;
}

function renderMatches(matches) {
  $('matches').innerHTML = matches.slice(0, 60).map(m => `
    <li>
      <div class="line"><span>${flag(m.home)} ${esc(m.home)} ${esc(m.score)} ${esc(m.away)} ${flag(m.away)}</span></div>
      <div class="sub"><span>${esc(m.date)} · ${esc(m.tournament)}</span>
        <span><span class="${tone(m.homeDelta)}">${signed(m.homeDelta, 1)}</span> / <span class="${tone(m.awayDelta)}">${signed(m.awayDelta, 1)}</span></span></div>
    </li>`).join('') || '<li>No matches since the last official ranking.</li>';
}

async function init() {
  const res = await fetch('data/rankings.json', { cache: 'no-cache' });
  state.data = await res.json();
  renderMeta(state.data);
  renderMovers(state.data.teams);
  renderTabs();
  renderTable();
  renderMatches(state.data.matches);

  $('search').addEventListener('input', e => { state.query = e.target.value; renderTable(); });
  $('confeds').addEventListener('click', e => {
    const c = e.target.dataset.confed;
    if (!c) return;
    state.confed = c;
    renderTabs();
    renderTable();
  });
  $('rows').addEventListener('click', e => {
    const row = e.target.closest('tr[data-code]');
    if (!row) return;
    state.open = state.open === row.dataset.code ? null : row.dataset.code;
    renderTable();
  });
}

init().catch(err => {
  $('rows').innerHTML = `<tr><td colspan="5">Could not load rankings: ${esc(err.message)}</td></tr>`;
});
