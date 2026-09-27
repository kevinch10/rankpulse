const FLAG = code => `https://api.fifa.com/api/v3/picture/flags-sq-2/${code}`;
const CONFEDS = ['All', 'FAV', 'UEFA', 'CONMEBOL', 'CONCACAF', 'CAF', 'AFC', 'OFC'];
const LIVE = 3;

const PAGE = 150;  // matches rendered before "Show more"
const state = { data: null, history: null, historyFrom: '', view: 'rankings', period: 7, limit: PAGE,
  confed: 'All', competition: '', compQuery: '', compActiveOnly: false, date: '', query: '', open: null, favs: loadFavs() };
const $ = id => document.getElementById(id);

// ---------- favourites (kept in this browser only) ----------

function loadFavs() {
  try { return new Set(JSON.parse(localStorage.getItem('favs') || '[]')); } catch { return new Set(); }
}

function toggleFav(code) {
  state.favs.has(code) ? state.favs.delete(code) : state.favs.add(code);
  try { localStorage.setItem('favs', JSON.stringify([...state.favs])); } catch {}
}

function starButton(code) {
  const on = state.favs.has(code);
  return `<button class="star" data-fav="${code}" aria-pressed="${on}" aria-label="${on ? 'Remove from' : 'Add to'} favourites">${on ? '★' : '☆'}</button>`;
}

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
const fmtDate = iso => new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const fmtDay = ymd => new Date(`${ymd}T12:00:00`).toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
const fmtTime = iso => new Date(iso).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
const signed = (n, digits = 2) => (n > 0 ? '+' : '') + n.toFixed(digits);
const tone = n => (n > 0 ? 'up' : n < 0 ? 'down' : 'flat');

function flag(code) {
  return `<img class="flag" src="${FLAG(code)}" alt="" loading="lazy" onerror="this.style.visibility='hidden'">`;
}

function moveBadge(n) {
  if (!n) return '<span class="move flat">–</span>';
  return `<span class="move ${tone(n)}">${n > 0 ? '▲' : '▼'}${Math.abs(n)}</span>`;
}

// ---------- header ----------

function renderMeta({ official, generatedAt, results, matchesSince }) {
  const counted = results.filter(m => m.counted).length;
  const items = [
    ['Official ranking', fmtDate(official.pubDate)],
    ['Matches applied', `${counted} since then`],
    ['Last refreshed', new Date(generatedAt).toLocaleString()],
  ];
  if (official.nextPubDate) items.push(['Next official release', fmtDate(official.nextPubDate)]);
  $('meta').innerHTML = items.map(([k, v]) => `<div><dt>${k}</dt><dd>${esc(v)}</dd></div>`).join('');
}

function renderMovers(teams) {
  const byPts = [...teams].sort((a, b) => b.pointsChange - a.pointsChange);
  const byRank = [...teams].sort((a, b) => b.rankChange - a.rankChange);
  const cards = [
    ['Biggest gain', byPts[0], signed(byPts[0].pointsChange)],
    ['Biggest drop', byPts.at(-1), signed(byPts.at(-1).pointsChange)],
    ['Most places up', byRank[0], `▲${byRank[0].rankChange}`],
  ];
  $('movers').innerHTML = cards.map(([label, t, value]) => `
    <div class="mover">
      <div class="label">${label}</div>
      <div class="team">${flag(t.code)}<span>${esc(t.name)}</span></div>
      <div class="value">${esc(value)}</div>
    </div>`).join('');
}

// ---------- results history ----------

const ymd = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

// The live file has results since the last official ranking; history.json
// has the year before that. It's fetched in the background after first paint.
async function loadHistory() {
  try {
    const res = await fetch('data/history.json', { cache: 'no-cache' });
    const h = await res.json();
    const seen = new Set(state.data.results.map(m => `${m.date}|${m.home}|${m.away}`));
    state.history = h.results.filter(m => !seen.has(`${m.date}|${m.home}|${m.away}`));
    state.historyFrom = h.from;
  } catch {
    state.history = [];
  }
  if (state.view === 'results') render();
}

function allResults() {
  return state.history ? state.data.results.concat(state.history) : state.data.results;
}

function periodStart() {
  const d = new Date();
  d.setDate(d.getDate() - state.period);
  return ymd(d);
}

// Results default to the past week; a chosen calendar day overrides the period.
function inPeriod(m) {
  return state.view !== 'results' || !!state.date || m.date >= periodStart();
}

function currentList() {
  return state.view === 'results' ? allResults() : state.data.fixtures;
}

// ---------- filters ----------

function teamMatchesFilter(code, name) {
  const q = state.query.trim().toLowerCase();
  return !q || name.toLowerCase().includes(q) || code.toLowerCase().includes(q);
}

function confedOK(code) {
  if (state.confed === 'All') return true;
  if (state.confed === 'FAV') return state.favs.has(code);
  return state.confedOf[code] === state.confed;
}

function matchVisible(m) {
  return (confedOK(m.home) || confedOK(m.away)) &&
    (!state.competition || m.competition === state.competition) &&
    (!state.date || m.date === state.date) &&
    inPeriod(m) &&
    (teamMatchesFilter(m.home, m.homeName) || teamMatchesFilter(m.away, m.awayName));
}

function renderControls() {
  $('confeds').innerHTML = CONFEDS.map(c =>
    `<button aria-pressed="${c === state.confed}" data-confed="${c}">${c === 'FAV' ? `★ Favourites${state.favs.size ? ` (${state.favs.size})` : ''}` : c}</button>`).join('');

  const sel = $('competition');
  sel.hidden = state.view === 'rankings';
  $('date-filter').hidden = sel.hidden;
  $('period').hidden = state.view !== 'results';
  $('period').value = String(state.period);
  $('period').disabled = !!state.date;
  $('search').placeholder = state.competition && !sel.hidden ? `Search teams in ${state.competition}…` : 'Search team…';
  if (!sel.hidden) {
    // Limit the calendar to the days that actually have matches in this tab.
    const days = currentList().map(m => m.date).sort();
    const input = $('date');
    input.min = (state.view === 'results' && state.historyFrom) || days[0] || '';
    input.max = days.at(-1) || '';
    if (state.date && (state.date < input.min || state.date > input.max)) state.date = '';
    input.value = state.date;
    $('date-clear').hidden = !state.date;
  }
  if (!sel.hidden) {
    $('comp-label').textContent = state.competition || 'All competitions';
    $('comp-btn').classList.toggle('active', !!state.competition);
    renderCompetitionList();
  }
  document.querySelectorAll('.views button').forEach(b =>
    b.setAttribute('aria-selected', b.dataset.view === state.view));
}

// ---------- competition picker ----------

let countsCache = { key: '', counts: new Map() };

// Matches per competition in the current tab and period (other filters ignored).
function competitionCount(c) {
  const key = `${state.view}|${state.period}|${state.date}|${state.history ? state.history.length : 0}`;
  if (countsCache.key !== key) {
    const counts = new Map();
    for (const m of currentList()) {
      if ((!state.date || m.date === state.date) && inPeriod(m)) counts.set(m.competition, (counts.get(m.competition) || 0) + 1);
    }
    countsCache = { key, counts };
  }
  return countsCache.counts.get(c.name) || 0;
}

function renderCompetitionList() {
  const q = state.compQuery.trim().toLowerCase();
  const comps = (state.data.competitions || []).filter(c =>
    (!q || c.name.toLowerCase().includes(q) || c.group.toLowerCase().includes(q)) &&
    (!state.compActiveOnly || competitionCount(c) > 0));
  const groups = new Map();
  for (const c of comps) {
    if (!groups.has(c.group)) groups.set(c.group, []);
    groups.get(c.group).push(c);
  }
  const item = (name, label, count, weight = '') => `
    <li role="option" tabindex="-1" data-comp="${esc(name)}" aria-selected="${state.competition === name}" class="${count === 0 ? 'empty-comp' : ''}">
      <span class="comp-name">${label}${weight ? `<small>${esc(weight)}</small>` : ''}</span>
      ${count === null ? '' : `<span class="comp-count">${count}</span>`}
    </li>`;
  const all = !q ? item('', 'All competitions', null) : '';
  $('comp-list').innerHTML = all + [...groups].map(([g, cs]) => `
    <li class="comp-group" role="presentation" data-confed="${esc(g)}">${esc(g)}</li>
    ${cs.map(c => item(c.name, esc(c.name), competitionCount(c), c.weight)).join('')}`).join('')
    || `<li class="comp-none" role="presentation">No competitions match “${esc(state.compQuery)}”</li>`;
}

function openCompetitionPicker(open) {
  $('comp-pop').hidden = !open;
  $('comp-btn').setAttribute('aria-expanded', open);
  if (open) {
    const pop = $('comp-pop');
    pop.style.left = '0px';
    const overflow = pop.getBoundingClientRect().right - (document.documentElement.clientWidth - 12);
    if (overflow > 0) pop.style.left = `${-overflow}px`;  // keep the popup on screen
    $('comp-search').value = state.compQuery;
    renderCompetitionList();
    $('comp-search').focus();
  }
}

function chooseCompetition(name) {
  state.competition = name;
  state.limit = PAGE;
  openCompetitionPicker(false);
  render();
}

// ---------- rankings ----------

function detailRow(t) {
  const ms = state.data.results.filter(m => m.counted && (m.home === t.code || m.away === t.code));
  const body = ms.length
    ? `<ul>${ms.map(m => {
        const d = m.home === t.code ? m.homeDelta : m.awayDelta;
        return `<li>${esc(m.date)} · ${esc(m.homeName)} ${scoreText(m)} ${esc(m.awayName)} · ${esc(m.competition)} (I=${m.importance}) · <span class="${tone(d)}">${signed(d)}</span></li>`;
      }).join('')}</ul>`
    : 'No matches since the last official ranking.';
  return `<tr class="detail"><td colspan="5">${body}</td></tr>`;
}

function renderRankings() {
  const teams = state.data.teams.filter(t => confedOK(t.code) && teamMatchesFilter(t.code, t.name));
  $('rows').innerHTML = teams.map(t => `
    <tr data-code="${t.code}" data-confed="${t.confed}" data-top="${t.liveRank <= 3 ? t.liveRank : ''}" aria-expanded="${state.open === t.code}">
      <td class="rank"><b>${t.liveRank}</b>${moveBadge(t.rankChange)}</td>
      <td class="num official hide-sm">${t.officialRank}</td>
      <td><div class="team-cell">${starButton(t.code)}${flag(t.code)}<span>${esc(t.name)} <span class="pill">${t.confed}</span></span></div></td>
      <td class="num">${t.livePoints.toFixed(2)}</td>
      <td class="num ${tone(t.pointsChange)}">${t.pointsChange ? signed(t.pointsChange) : '–'}</td>
    </tr>${state.open === t.code ? detailRow(t) : ''}`).join('');
  return teams.length;
}

// ---------- results & fixtures ----------

function scoreText(m) {
  if (m.homeScore == null) return 'v';
  const pens = m.homePens != null ? ` (${m.homePens}–${m.awayPens} p)` : '';
  return `${m.homeScore}–${m.awayScore}${pens}`;
}

const OUTCOMES = [['win', 'W'], ['draw', 'D'], ['loss', 'L'], ['pensWin', 'W pens'], ['pensLoss', 'L pens']];

function predictionBlock(m) {
  if (!m.prediction) return '';
  const col = (side, name) => `
    <div class="pred-side">
      <div class="pred-name">${esc(name)}</div>
      <div class="pred-chips">${OUTCOMES.filter(([k]) => k in m.prediction[side]).map(([k, label]) => {
        const v = m.prediction[side][k];
        return `<span class="pred ${tone(v)}"><b>${label}</b>${signed(v, 1)}</span>`;
      }).join('')}</div>
    </div>`;
  return `
    <div class="prediction">
      <div class="pred-head">Points at stake <span>I=${m.importance}${m.knockout ? ' · knockout' : ''}</span></div>
      <div class="pred-grid">${col('home', m.homeName)}${col('away', m.awayName)}</div>
    </div>`;
}

function matchRow(m, fixture) {
  const side = (code, name, delta, align) => `
    <span class="side ${align}">${align === 'r' ? '' : flag(code)}<span class="nm">${esc(name)}</span>${align === 'r' ? flag(code) : ''}
      ${m.counted ? `<span class="delta ${tone(delta)}">${signed(delta, 1)}</span>` : ''}</span>`;
  const middle = fixture
    ? `<span class="score time">${fmtTime(m.kickoff)}</span>`
    : `<span class="score">${scoreText(m)}</span>`;
  const tags = [
    m.status === LIVE ? '<span class="tag live">Live</span>' : '',
    m.counted ? `<span class="tag">I=${m.importance}</span>` : '',
    !fixture && !m.counted && m.status !== LIVE ? '<span class="tag muted" title="Already included in the official ranking">In official</span>' : '',
    m.note ? `<span class="tag" title="${esc(m.note)}">Corrected</span>` : '',
    m.source && m.source !== 'FIFA' && m.source !== 'Manual'
      ? `<span class="tag muted" title="FIFA's feed doesn't carry this match yet; result from ${esc(m.source)}">via ${m.source === 'Wikipedia' ? 'Wikipedia' : 'community data'}</span>` : '',
  ].join('');
  return `
    <li class="match${state.favs.has(m.home) || state.favs.has(m.away) ? ' is-fav' : ''}" data-confed="${state.confedOf[m.home] || ''}">
      <div class="teams">${side(m.home, m.homeName, m.homeDelta, 'l')}${middle}${side(m.away, m.awayName, m.awayDelta, 'r')}</div>
      <div class="sub">${esc(m.competition)}${m.stage && !m.stage.startsWith('Friendlies') ? ` · ${esc(m.stage)}` : ''}${m.city ? ` · ${esc(m.city)}` : ''} ${tags}</div>
      ${fixture ? predictionBlock(m) : ''}
    </li>`;
}

function renderMatchList(el, list, fixture) {
  const all = list.filter(matchVisible);
  const shown = all.slice(0, state.limit);
  const days = new Map();
  for (const m of shown) {
    if (!days.has(m.date)) days.set(m.date, []);
    days.get(m.date).push(m);
  }
  el.innerHTML = [...days].map(([day, ms]) => `
    <section class="day">
      <h3>${fmtDay(day)} <span>${ms.length} match${ms.length === 1 ? '' : 'es'}</span></h3>
      <ol class="matches">${ms.map(m => matchRow(m, fixture)).join('')}</ol>
    </section>`).join('') +
    (all.length > shown.length
      ? `<button class="more" id="show-more">Show more <span>${all.length - shown.length} older</span></button>` : '') +
    (!fixture && !state.date && state.period > 7 && !state.history
      ? `<p class="loading">Loading older results…</p>` : '');
  return all.length;
}

// ---------- render ----------

function render() {
  renderControls();
  for (const v of ['rankings', 'results', 'fixtures']) $(`view-${v}`).hidden = v !== state.view;
  const n = state.view === 'rankings' ? renderRankings()
    : state.view === 'results' ? renderMatchList($('view-results'), allResults(), false)
    : renderMatchList($('view-fixtures'), state.data.fixtures, true);
  $('empty').hidden = n > 0;
  $('empty').textContent = state.confed === 'FAV' && !state.favs.size
    ? 'No favourites yet — tap ☆ next to a team in Rankings.'
    : state.view === 'results' && !state.date
      ? `No ${state.competition ? `${state.competition} ` : ''}matches in the ${$('period').selectedOptions[0].text.toLowerCase()}${state.period < 365 ? ' — try a longer period.' : '.'}`
    : state.competition && !state.date && !state.query
      ? `No ${state.competition} matches scheduled yet.`
    : state.date ? `No matches on ${fmtDay(state.date)}.` : 'Nothing matches these filters.';
}

async function init() {
  const res = await fetch('data/rankings.json', { cache: 'no-cache' });
  state.data = await res.json();
  state.confedOf = Object.fromEntries(state.data.teams.map(t => [t.code, t.confed]));
  renderMeta(state.data);
  renderMovers(state.data.teams);
  const weekAgo = new Date(); weekAgo.setDate(weekAgo.getDate() - 7);
  $('results-count').textContent = state.data.results.filter(m => m.date >= ymd(weekAgo)).length;
  $('results-count').title = 'Results in the past week';
  $('fixtures-count').textContent = state.data.fixtures.length;
  render();
  loadHistory();

  document.querySelector('.views').addEventListener('click', e => {
    const b = e.target.closest('button[data-view]');
    if (b) { state.view = b.dataset.view; state.limit = PAGE; render(); }
  });
  $('search').addEventListener('input', e => { state.query = e.target.value; render(); });
  $('comp-btn').addEventListener('click', () => openCompetitionPicker($('comp-pop').hidden));
  $('comp-search').addEventListener('input', e => { state.compQuery = e.target.value; renderCompetitionList(); });
  $('comp-active').addEventListener('change', e => { state.compActiveOnly = e.target.checked; renderCompetitionList(); });
  $('comp-search').addEventListener('keydown', e => {
    if (e.key === 'Enter') {
      const first = $('comp-list').querySelector('li[data-comp]:not([data-comp=""])') || $('comp-list').querySelector('li[data-comp]');
      if (first) chooseCompetition(first.dataset.comp);
    }
    if (e.key === 'ArrowDown') { e.preventDefault(); $('comp-list').querySelector('li[data-comp]')?.focus(); }
  });
  $('comp-list').addEventListener('keydown', e => {
    const items = [...$('comp-list').querySelectorAll('li[data-comp]')];
    const i = items.indexOf(document.activeElement);
    if (e.key === 'ArrowDown') { e.preventDefault(); items[Math.min(i + 1, items.length - 1)]?.focus(); }
    if (e.key === 'ArrowUp') { e.preventDefault(); i <= 0 ? $('comp-search').focus() : items[i - 1].focus(); }
    if (e.key === 'Enter' && i >= 0) chooseCompetition(items[i].dataset.comp);
  });
  $('comp-list').addEventListener('click', e => {
    const li = e.target.closest('li[data-comp]');
    if (li) chooseCompetition(li.dataset.comp);
  });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') openCompetitionPicker(false); });
  document.addEventListener('click', e => { if (!e.target.closest('#competition')) openCompetitionPicker(false); });
  $('date').addEventListener('change', e => { state.date = e.target.value; state.limit = PAGE; render(); });
  $('period').addEventListener('change', e => { state.period = Number(e.target.value); state.limit = PAGE; render(); });
  document.querySelector('main').addEventListener('click', e => {
    if (e.target.closest('#show-more')) { state.limit += PAGE; render(); }
  });
  $('date-clear').addEventListener('click', () => { state.date = ''; render(); });
  $('confeds').addEventListener('click', e => {
    const c = e.target.dataset.confed;
    if (c) { state.confed = c; render(); }
  });
  $('rows').addEventListener('click', e => {
    const star = e.target.closest('button[data-fav]');
    if (star) { toggleFav(star.dataset.fav); render(); return; }
    const row = e.target.closest('tr[data-code]');
    if (!row) return;
    state.open = state.open === row.dataset.code ? null : row.dataset.code;
    render();
  });
}

init().catch(err => {
  $('rows').innerHTML = `<tr><td colspan="5">Could not load rankings: ${esc(err.message)}</td></tr>`;
});

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
