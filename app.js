const FLAG = code => `https://api.fifa.com/api/v3/picture/flags-sq-2/${code}`;
const CONFEDS = ['All', 'FAV', 'UEFA', 'CONMEBOL', 'CONCACAF', 'CAF', 'AFC', 'OFC'];
const REGIONS = { UEFA: 'Europe', CONMEBOL: 'South America', CONCACAF: 'North & Central America', CAF: 'Africa', AFC: 'Asia', OFC: 'Oceania' };
const LIVE = 3;

const PAGE = 150;  // matches rendered before "Show more"
const RANK_PAGE = 50;  // teams per page in Rankings
const FIFA_CALENDAR = 'https://api.fifa.com/api/v3/calendar/matches';
// Data is rebuilt every 15 minutes and published on GitHub Pages. Copies of the site on
// other hosts (e.g. Vercel) read it from there, so they never need redeploying for new data.
const DATA_BASE = location.hostname.endsWith('github.io') || ['localhost', '127.0.0.1'].includes(location.hostname)
  ? 'data/' : 'https://kevinch10.github.io/world-football-rankings/data/';
const saved = loadPrefs();
const state = { data: null, history: null, historyFrom: '', historyFailed: false,
  view: ['rankings', 'results', 'fixtures', 'fantasy'].includes(location.hash.slice(1)) ? location.hash.slice(1) : (saved.view || 'rankings'),
  period: saved.period || 7, limit: PAGE, confed: saved.confed || 'All',
  competition: '', compQuery: '', compActiveOnly: false, date: '', query: '', open: null, favs: loadFavs(),
  rankPage: 0, base: null, live: new Map(), liveCheckedAt: null };
const $ = id => document.getElementById(id);

// ---------- preferences (this browser only) ----------

function loadPrefs() {
  try { return JSON.parse(localStorage.getItem('prefs') || '{}'); } catch { return {}; }
}

function savePrefs() {
  try { localStorage.setItem('prefs', JSON.stringify({ view: state.view, confed: state.confed, period: state.period })); } catch {}
  if (location.hash.slice(1) !== state.view) history.replaceState(null, '', `#${state.view}`);
}

// ---------- favourites (kept in this browser only) ----------

function loadFavs() {
  try { return new Set(JSON.parse(localStorage.getItem('favs') || '[]')); } catch { return new Set(); }
}

function toggleFav(code) {
  const removing = state.favs.has(code);
  removing ? state.favs.delete(code) : state.favs.add(code);
  try { localStorage.setItem('favs', JSON.stringify([...state.favs])); } catch {}
  const name = state.data.teams.find(t => t.code === code)?.name || code;
  toast(removing ? `Removed ${name} from favourites` : `Added ${name} to favourites`, removing ? () => { toggleFav(code); render(); } : null);
}

let toastTimer;
function toast(text, undo) {
  const el = $('toast');
  el.innerHTML = `<span>${esc(text)}</span>${undo ? '<button type="button">Undo</button>' : ''}`;
  el.hidden = false;
  if (undo) el.querySelector('button').onclick = () => { el.hidden = true; undo(); };
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 5000);
}

function starButton(code) {
  const on = state.favs.has(code);
  return `<button class="star" data-fav="${code}" aria-pressed="${on}" aria-label="${on ? 'Remove from' : 'Add to'} favourites">${on ? '★' : '☆'}</button>`;
}

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
const fmtDate = iso => new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const fmtDay = ymd => new Date(`${ymd}T12:00:00`).toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
const fmtTime = iso => new Date(iso).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
const fmtShort = ymd => new Date(`${ymd}T12:00:00`).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' });

function ago(iso) {
  const mins = Math.round((Date.now() - new Date(iso)) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  return hours < 48 ? `${hours} h ago` : `${Math.round(hours / 24)} days ago`;
}

// Everyday names and accent-free spellings, so "south korea" or "cote" find the team.
const fold = s => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
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
  const stale = Date.now() - new Date(generatedAt) > 3 * 3600 * 1000;
  const items = [
    ['Last official FIFA ranking', fmtDate(official.pubDate)],
    ['Matches counted since', String(counted)],
    ['Updated', ago(generatedAt), new Date(generatedAt).toLocaleString(), stale],
  ];
  if (state.liveCheckedAt) items.push(['Live scores', `checked ${ago(state.liveCheckedAt.toISOString())}`]);
  if (official.nextPubDate) items.push(['Next official release', fmtDate(official.nextPubDate)]);
  $('meta').innerHTML = items.map(([k, v, title, warn]) =>
    `<div class="${warn ? 'stale' : ''}" ${title ? `title="${esc(title)}"` : ''}><dt>${k}</dt><dd>${esc(v)}${warn ? ' · may be out of date' : ''}</dd></div>`).join('');
}

function renderMovers(teams) {
  const byPts = [...teams].sort((a, b) => b.pointsChange - a.pointsChange);
  const byRank = [...teams].sort((a, b) => b.rankChange - a.rankChange);
  const cards = [
    ['Biggest gain', byPts[0], signed(byPts[0].pointsChange)],
    ['Biggest drop', byPts.at(-1), signed(byPts.at(-1).pointsChange)],
    ['Most places up', byRank[0], `▲${byRank[0].rankChange}`],
    ['Most places down', byRank.at(-1), `▼${-byRank.at(-1).rankChange}`],
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
    const res = await fetch(`${DATA_BASE}history.json`, { cache: 'no-cache' });
    const h = await res.json();
    const seen = new Set(state.data.results.map(m => `${m.date}|${m.home}|${m.away}`));
    state.history = h.results.filter(m => !seen.has(`${m.date}|${m.home}|${m.away}`));
    state.historyFrom = h.from;
    state.historyFailed = false;
  } catch {
    state.history = null;
    state.historyFailed = true;
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
  const q = fold(state.query.trim());
  if (!q) return true;
  return [name, code, ...(state.aliasesOf[code] || [])].some(s => fold(s).includes(q));
}

function filtersActive() {
  return state.confed !== 'All' || !!state.competition || !!state.date || !!state.query.trim() ||
    (state.view === 'results' && state.period !== 7);
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
  $('confeds').innerHTML = CONFEDS.map(c => {
    const label = c === 'FAV' ? `★ Favourites${state.favs.size ? ` (${state.favs.size})` : ''}`
      : c === 'All' ? 'All' : `${c} <small>${REGIONS[c]}</small>`;
    return `<button aria-pressed="${c === state.confed}" data-confed="${c}" ${REGIONS[c] ? `title="${REGIONS[c]}"` : ''}>${label}</button>`;
  }).join('');
  $('clear-filters').hidden = !filtersActive();

  const sel = $('competition');
  sel.hidden = state.view === 'rankings';
  $('date-filter').hidden = sel.hidden;
  $('period').hidden = state.view !== 'results';
  $('period').value = String(state.period);
  $('period').disabled = !!state.date;
  $('search').placeholder = state.competition && !sel.hidden ? `Search teams in ${state.competition}…` : 'Search team, e.g. Brazil or South Korea';
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
        return `<li>${fmtShort(m.date)} · ${esc(m.homeName)} ${scoreText(m)} ${esc(m.awayName)} · ${esc(m.competition)} (weight ${m.importance}) · <span class="${tone(d)}">${signed(d)}</span></li>`;
      }).join('')}</ul>`
    : 'No matches since the last official ranking.';
  return `<tr class="detail"><td colspan="5">${body}</td></tr>`;
}

function renderRankings() {
  const all = state.data.teams.filter(t => confedOK(t.code) && teamMatchesFilter(t.code, t.name));
  const pages = Math.max(1, Math.ceil(all.length / RANK_PAGE));
  state.rankPage = Math.min(state.rankPage, pages - 1);
  const start = state.rankPage * RANK_PAGE;
  const teams = all.slice(start, start + RANK_PAGE);
  renderPager(all.length, pages, start, teams.length);
  $('rows').innerHTML = teams.map(t => `
    <tr data-code="${t.code}" data-confed="${t.confed}" data-top="${t.liveRank <= 3 ? t.liveRank : ''}" aria-expanded="${state.open === t.code}">
      <td class="rank"><b>${t.liveRank}</b>${moveBadge(t.rankChange)}</td>
      <td class="num official hide-sm">${t.officialRank}</td>
      <td><div class="team-cell">${starButton(t.code)}${flag(t.code)}<span>${esc(t.name)} <span class="pill">${t.confed}</span></span></div></td>
      <td class="num">${t.livePoints.toFixed(2)}</td>
      <td class="num ${tone(t.pointsChange)}">${t.pointsChange ? signed(t.pointsChange) : '–'}</td>
    </tr>${state.open === t.code ? detailRow(t) : ''}`).join('');
  return all.length;
}

function renderPager(total, pages, start, count) {
  const el = $('pager');
  el.hidden = pages <= 1;
  if (pages <= 1) return;
  const p = state.rankPage;
  const btn = (label, page, extra = '') =>
    `<button type="button" data-page="${page}" ${extra}>${label}</button>`;
  el.innerHTML = `
    ${btn('‹ Previous', p - 1, p === 0 ? 'disabled' : '')}
    <span class="pages">${Array.from({ length: pages }, (_, i) =>
      btn(i + 1, i, i === p ? 'aria-current="page"' : '')).join('')}</span>
    <span class="range">${start + 1}–${start + count} of ${total}</span>
    ${btn('Next ›', p + 1, p === pages - 1 ? 'disabled' : '')}`;
}

function setRankPage(page) {
  state.rankPage = page;
  render();
  document.querySelector('.views').scrollIntoView({ behavior: 'smooth', block: 'start' });
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
        return `<span class="pred ${tone(v)}"><b>${label}</b>${signed(v)}</span>`;
      }).join('')}</div>
    </div>`;
  return `
    <div class="prediction">
      <div class="pred-head">Points at stake <button class="help-q" type="button" data-help="help-weights" aria-label="What do these numbers mean?">?</button>
        <span>Match weight ${m.importance}${m.knockout ? ' · knockout: the loser keeps its points' : ''}</span></div>
      <div class="pred-grid">${col('home', m.homeName)}${col('away', m.awayName)}</div>
    </div>`;
}

function matchRow(m, fixture) {
  const side = (code, name, delta, align) => `
    <span class="side ${align}">${align === 'r' ? '' : flag(code)}<button class="nm team-link" data-team="${code}" title="Open ${esc(name)} in Rankings">${esc(name)}</button>${align === 'r' ? flag(code) : ''}
      ${m.counted ? `<span class="delta ${tone(delta)}">${signed(delta)}</span>` : ''}</span>`;
  const middle = fixture
    ? `<span class="score time">${fmtTime(m.kickoff)}</span>`
    : `<span class="score">${scoreText(m)}</span>`;
  const tags = [
    m.status === LIVE ? '<span class="tag live" title="In progress — points are added at full time">Live</span>' : '',
    m.liveUpdated && m.status !== LIVE && m.counted ? '<span class="tag" title="Scored from FIFA\'s live result; confirmed at the next update">Just finished</span>' : '',
    m.counted ? `<span class="tag" title="How much this match counts in FIFA's formula">Weight ${m.importance}</span>` : '',
    !fixture && !m.counted && m.status !== LIVE ? '<span class="tag muted" title="Played before the last official ranking, so it is already included there">In official ranking</span>' : '',
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
    (!fixture && state.historyFailed && (state.period > 7 || state.date)
      ? `<p class="notice">Couldn't load older results — check your connection. <button type="button" id="retry-history">Try again</button></p>`
      : !fixture && !state.date && state.period > 7 && !state.history
      ? `<p class="loading"><span class="spinner" aria-hidden="true"></span> Loading older results…</p>` : '');
  return all.length;
}

// ---------- fantasy matches ----------

const MULTIPLIERS = Array.from({ length: 12 }, (_, i) => (i + 1) * 5);  // 5, 10 … 60 (FIFA's highest)
const fantasyToday = () => ymd(new Date());
const pairKey = (a, b) => [a, b].sort().join('-');

// Free: one pairing per day (its match type can be changed freely). Kept in this browser.
function fantasyUsed() {
  try {
    const q = JSON.parse(localStorage.getItem('fantasy') || '{}');
    return q.day === fantasyToday() ? q.pair : null;
  } catch { return null; }
}

function recordFantasy(pair) {
  try { localStorage.setItem('fantasy', JSON.stringify({ day: fantasyToday(), pair })); } catch {}
}

function setupFantasy() {
  const teams = [...state.data.teams].sort((a, b) => a.name.localeCompare(b.name));
  const opts = sel => `<option value="">Choose a team</option>` +
    teams.map(t => `<option value="${t.code}" ${t.code === sel ? 'selected' : ''}>${esc(t.name)} (#${t.liveRank})</option>`).join('');
  const firstFav = [...state.favs][0] || '';
  $('fa').innerHTML = opts(firstFav);
  $('fb').innerHTML = opts('');
  $('fmult').innerHTML = MULTIPLIERS.map(m => `<option value="${m}" ${m === 10 ? 'selected' : ''}>×${m}</option>`).join('');
  const changed = () => { state.fantasyShown = null; renderFantasy(); };
  $('fa').onchange = changed;
  $('fb').onchange = changed;
  $('fmult').onchange = () => renderFantasy();
  $('fko').onchange = () => renderFantasy();
  $('fplay').onclick = () => {
    const a = $('fa').value, b = $('fb').value;
    if (!a || !b) return;
    const pair = pairKey(a, b), used = fantasyUsed();
    if (used && used !== pair) return;
    recordFantasy(pair);
    state.fantasyShown = pair;
    renderFantasy();
  };
}

function renderFantasy() {
  const a = $('fa').value, b = $('fb').value;
  // Error prevention: a team can't play itself.
  [...$('fb').options].forEach(o => { o.disabled = !!o.value && o.value === a; });
  [...$('fa').options].forEach(o => { o.disabled = !!o.value && o.value === b; });
  const pair = a && b ? pairKey(a, b) : null;
  const used = fantasyUsed();
  const blocked = pair && used && used !== pair;
  const btn = $('fplay');
  btn.disabled = !pair || blocked || pair === state.fantasyShown;
  btn.textContent = pair && pair === state.fantasyShown ? 'Showing this match' : blocked ? 'Free match used today' : 'Play fantasy match';
  const names = key => key.split('-').map(c => state.data.teams.find(t => t.code === c)?.name || c).join(' v ');
  $('fquota').innerHTML = used
    ? `Today's free match: <b>${esc(names(used))}</b>. Change its multiplier as often as you like; a new pairing is available tomorrow. Unlimited fantasy matches (and no ads) come with <b>Premium in the iPhone app</b>.`
    : '1 free fantasy match per day. Unlimited matches and no ads come with Premium in the iPhone app.';

  if (!pair || pair !== state.fantasyShown) { $('fresult').innerHTML = ''; return; }
  const weight = Number($('fmult').value), knockout = $('fko').checked;
  const A = state.data.teams.find(t => t.code === a), B = state.data.teams.find(t => t.code === b);
  const outcomes = [[`${A.name} win`, 1, 0]];
  if (knockout) outcomes.push([`${A.name} win on penalties`, 0.75, 0.5], [`${B.name} win on penalties`, 0.5, 0.75]);
  else outcomes.push(['Draw', 0.5, 0.5]);
  outcomes.push([`${B.name} win`, 0, 1]);

  const rankAfter = (team, pts, other, otherPts) => 1 + state.data.teams.filter(t => {
    if (t.code === team.code) return false;
    const p = t.code === other.code ? otherPts : t.livePoints;
    return p > pts || (p === pts && t.officialRank < team.officialRank);
  }).length;

  const row = (t, d, rank) => {
    const move = t.liveRank - rank;
    return `<div class="f-row">${flag(t.code)}<span class="f-name">${esc(t.name)}</span>
      <span class="f-delta ${tone(d)}">${signed(d)}</span>
      <span class="f-rank">#${t.liveRank} → #${rank} ${move ? moveBadge(move) : ''}</span></div>`;
  };
  $('fresult').innerHTML = (knockout ? '<p class="fantasy-note">Knockout: a draw goes to penalties, and the losing team keeps its points.</p>' : '') +
    outcomes.map(([label, wa, wb]) => {
      const eh = expected(A.livePoints, B.livePoints);
      let da = weight * (wa - eh), db = weight * (wb - (1 - eh));
      if (knockout) { da = Math.max(da, 0); db = Math.max(db, 0); }
      da = round2(da); db = round2(db);
      const pa = A.livePoints + da, pb = B.livePoints + db;
      return `<section class="f-outcome"><h3>${esc(label)}</h3>
        ${row(A, da, rankAfter(A, pa, B, pb))}${row(B, db, rankAfter(B, pb, A, pa))}</section>`;
    }).join('');
}

// ---------- live scores (straight from FIFA while matches are on) ----------

const FINISHED = 0;
const expected = (p, q) => 1 / (10 ** (-(p - q) / 600) + 1);
const round2 = n => Math.round(n * 100) / 100;

// Server data plus the live scores fetched from FIFA since. Matches that have
// finished since the last server update are scored here with FIFA's formula,
// so the table moves at full time instead of at the next update.
function derive(base, live) {
  const teams = base.teams.map(t => ({ ...t }));
  const byCode = Object.fromEntries(teams.map(t => [t.code, t]));
  const points = Object.fromEntries(teams.map(t => [t.code, t.livePoints]));
  const results = base.results.map(m => ({ ...m }));
  const fixtures = [];
  for (const f of base.fixtures) {
    const l = f.fifaId && live.get(f.fifaId);
    if (l && (l.status === LIVE || l.status === FINISHED)) results.push({ ...f }); else fixtures.push(f);
  }
  const finished = [];
  for (const m of results) {
    const l = m.fifaId && live.get(m.fifaId);
    if (!l) continue;
    Object.assign(m, l, { liveUpdated: true });
    if (l.status === FINISHED && !m.counted && m.importance) finished.push(m);
  }
  finished.sort((a, b) => a.kickoff.localeCompare(b.kickoff));
  for (const m of finished) {
    if (!(m.home in points) || !(m.away in points)) continue;
    let wh, wa;
    if (m.homeScore !== m.awayScore) { wh = m.homeScore > m.awayScore ? 1 : 0; wa = 1 - wh; }
    else if (m.homePens != null) [wh, wa] = m.homePens > m.awayPens ? [0.75, 0.5] : [0.5, 0.75];
    else wh = wa = 0.5;
    const eh = expected(points[m.home], points[m.away]);
    let dh = m.importance * (wh - eh), da = m.importance * (wa - (1 - eh));
    if (m.knockout) { dh = Math.max(dh, 0); da = Math.max(da, 0); }
    dh = round2(dh); da = round2(da);
    points[m.home] += dh; points[m.away] += da;
    Object.assign(m, { counted: true, homeDelta: dh, awayDelta: da, prediction: undefined });
  }
  for (const t of teams) {
    t.livePoints = round2(points[t.code]);
    t.pointsChange = round2(t.livePoints - t.officialPoints);
  }
  teams.sort((a, b) => b.livePoints - a.livePoints || a.officialRank - b.officialRank);
  teams.forEach((t, i) => { t.liveRank = i + 1; t.rankChange = t.officialRank - t.liveRank; });
  results.sort((a, b) => b.kickoff.localeCompare(a.kickoff));
  return { ...base, teams, results, fixtures };
}

// Matches worth asking FIFA about: live now, or due to start or finish soon.
function liveCandidates() {
  const now = Date.now();
  const soon = m => { const k = new Date(m.kickoff).getTime(); return k < now + 10 * 60e3 && k > now - 4 * 3600e3; };
  return [...state.base.results.filter(m => m.status === LIVE), ...state.base.fixtures.filter(soon)].filter(m => m.fifaId);
}

async function fetchLive() {
  const wanted = new Set(liveCandidates().map(m => m.fifaId));
  if (!wanted.size) { state.liveCheckedAt = null; return false; }
  const day = offset => { const d = new Date(); d.setUTCDate(d.getUTCDate() + offset); return d.toISOString().slice(0, 10); };
  let url = `${FIFA_CALENDAR}?language=en&count=500&from=${day(-1)}T00:00:00Z&to=${day(1)}T23:59:59Z`;
  for (let page = 0; page < 6 && url; page++) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`fifa ${res.status}`);
    const d = await res.json();
    for (const m of d.Results || []) {
      if (!wanted.has(m.IdMatch)) continue;
      state.live.set(m.IdMatch, {
        status: m.MatchStatus, homeScore: m.HomeTeamScore, awayScore: m.AwayTeamScore,
        homePens: m.HomeTeamPenaltyScore, awayPens: m.AwayTeamPenaltyScore,
      });
    }
    url = d.ContinuationToken && d.Results?.length
      ? `${FIFA_CALENDAR}?language=en&count=500&from=${day(-1)}T00:00:00Z&to=${day(1)}T23:59:59Z&continuationToken=${encodeURIComponent(d.ContinuationToken)}`
      : null;
  }
  state.liveCheckedAt = new Date();
  return true;
}

function applyData() {
  state.data = derive(state.base, state.live);
  renderMeta(state.data);
  renderMovers(state.data.teams);
  const weekAgo = new Date(); weekAgo.setDate(weekAgo.getDate() - 7);
  $('results-count').textContent = state.data.results.filter(m => m.date >= ymd(weekAgo)).length;
  $('fixtures-count').textContent = state.data.fixtures.length;
  render();
}

// Live scores every minute while a match is on; fresh server data every 10.
function startLiveLoop() {
  let lastServer = Date.now();
  const tick = async () => {
    if (document.hidden) return;
    try {
      if (Date.now() - lastServer > 10 * 60e3) {
        const res = await fetch(`${DATA_BASE}rankings.json`, { cache: 'no-cache' });
        if (res.ok) { state.base = await res.json(); lastServer = Date.now(); }
      }
      await fetchLive();
      applyData();
    } catch { /* keep showing what we have; try again next minute */ }
  };
  tick();
  setInterval(tick, 60e3);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });
}

// ---------- render ----------

function nearestMatchDay(day) {
  const days = [...new Set(currentList().map(m => m.date))];
  return days.sort((a, b) => Math.abs(new Date(a) - new Date(day)) - Math.abs(new Date(b) - new Date(day)))[0];
}

function render() {
  savePrefs();
  renderControls();
  for (const v of ['rankings', 'results', 'fixtures', 'fantasy']) $(`view-${v}`).hidden = v !== state.view;
  document.querySelector('.controls').hidden = state.view === 'fantasy';
  if (state.view === 'fantasy') {
    if (!state.fantasyReady) { setupFantasy(); state.fantasyReady = true; }
    renderFantasy();
    $('empty').hidden = true;
    $('pager').hidden = true;
    return;
  }
  if (state.view !== 'rankings') $('pager').hidden = true;
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
  if (n === 0 && state.date && !state.query && !state.competition && state.confed === 'All') {
    const near = nearestMatchDay(state.date);
    if (near && near !== state.date) {
      $('empty').innerHTML = `No matches on ${fmtDay(state.date)}. <button type="button" class="linkish" data-goto-day="${near}">Show ${fmtDay(near)}</button>`;
    }
  }
}

async function init() {
  const res = await fetch(`${DATA_BASE}rankings.json`, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`server ${res.status}`);
  state.base = await res.json();
  state.data = state.base;
  state.confedOf = Object.fromEntries(state.data.teams.map(t => [t.code, t.confed]));
  state.aliasesOf = Object.fromEntries(state.data.teams.map(t => [t.code, t.aliases || []]));
  setInterval(() => renderMeta(state.data), 60000);  // keep "Updated … ago" current
  renderMeta(state.data);
  renderMovers(state.data.teams);
  const weekAgo = new Date(); weekAgo.setDate(weekAgo.getDate() - 7);
  $('results-count').textContent = state.data.results.filter(m => m.date >= ymd(weekAgo)).length;
  $('results-count').title = 'Results in the past week';
  $('fixtures-count').textContent = state.data.fixtures.length;
  render();
  loadHistory();
  if (state.bound) return;
  startLiveLoop();  // a retry after a failed load mustn't bind handlers twice
  state.bound = true;

  document.querySelector('.views').addEventListener('click', e => {
    const b = e.target.closest('button[data-view]');
    if (b) { state.view = b.dataset.view; state.limit = PAGE; render(); }
  });
  $('search').addEventListener('input', e => { state.query = e.target.value; state.rankPage = 0; render(); });
  $('pager').addEventListener('click', e => {
    const b = e.target.closest('button[data-page]');
    if (b && !b.disabled) setRankPage(Number(b.dataset.page));
  });
  $('clear-filters').addEventListener('click', () => {
    Object.assign(state, { confed: 'All', competition: '', date: '', query: '', period: 7, limit: PAGE, rankPage: 0 });
    $('search').value = '';
    render();
  });
  document.addEventListener('keydown', e => {
    if (e.key === '/' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) {
      e.preventDefault(); $('search').focus();
    }
  });
  $('help-open').addEventListener('click', () => $('help').showModal());
  document.addEventListener('click', e => {
    const q = e.target.closest('[data-help]');
    if (q) { $('help').showModal(); document.getElementById(q.dataset.help)?.scrollIntoView(); }
    const goto = e.target.closest('[data-goto-day]');
    if (goto) { state.date = goto.dataset.gotoDay; render(); }
    if (e.target.closest('#retry-history')) { state.historyFailed = false; render(); loadHistory(); }
  });
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
    if (e.target.closest('#show-more')) { state.limit += PAGE; render(); return; }
    // A team name in a match opens that team, expanded, in the Rankings tab.
    const link = e.target.closest('.team-link');
    if (link) {
      state.view = 'rankings'; state.confed = 'All'; state.query = ''; state.open = link.dataset.team;
      const rank = state.data.teams.find(t => t.code === link.dataset.team)?.liveRank || 1;
      state.rankPage = Math.floor((rank - 1) / RANK_PAGE);
      $('search').value = '';
      render();
      document.querySelector(`tr[data-code="${link.dataset.team}"]`)?.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  });
  $('date-clear').addEventListener('click', () => { state.date = ''; render(); });
  $('confeds').addEventListener('click', e => {
    const c = e.target.closest('[data-confed]')?.dataset.confed;
    if (c) { state.confed = c; state.rankPage = 0; render(); }
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

function start() {
  init().catch(err => {
    // Say what went wrong in plain words, and offer a way out.
    const offline = !navigator.onLine;
    const why = offline ? "You're offline. Check your connection and try again."
      : /server/.test(err.message) ? 'The rankings server is having a problem right now. Please try again in a minute.'
      : "The rankings couldn't be loaded. Please try again.";
    $('rows').innerHTML = `<tr><td colspan="5" class="error-row"><b>Couldn't load the rankings.</b> ${why}
      <button type="button" id="retry">Try again</button></td></tr>`;
    $('retry').onclick = () => {
      $('rows').innerHTML = '<tr><td colspan="5" class="loading-row"><span class="spinner" aria-hidden="true"></span> Loading the latest rankings…</td></tr>';
      start();
    };
  });
}
start();

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
