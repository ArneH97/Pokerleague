/**
 * De zaalpagina voor een oude tv.
 *
 * **Waarom dit geen component is.** Elk ander scherm van PokerLeague is een
 * React-pagina met Tailwind erop, en allebei die dingen vragen een browser
 * van maart 2023: Next zegt Chrome 111, Tailwind zegt Chrome 111. Een Samsung
 * uit 2023 draait Chromium 94, een uit 2020 draait 69. Daar valt niet alleen
 * de opmaak weg maar struikelt ook de code zelf — wat je overhoudt is een
 * kale lijst links op een wit vlak. Dat is wat er bij Cutoff op de tv stond.
 *
 * Dus staat hier geen component maar een tekst: één string HTML met zijn
 * eigen CSS en een klein stuk ouderwets JavaScript erin. Geen React, geen
 * Tailwind, geen bundel. Alles wat erin staat kende een browser van 2019 al,
 * en dat is te controleren — `zaalscherm.test.ts` leest deze tekst na op de
 * dingen die een oude tv niet kent, zodat er niet stilletjes een `color-mix`
 * insluipt zodra iemand hier iets bijzet.
 *
 * **Wat de pagina zelf doet.** Ze telt lokaal af en vraagt elke tien seconden
 * de stand opnieuw. Dat is geen compromis maar dezelfde aanpak als de echte
 * klok: de server geeft niet "nog 7:13" maar "level 4 begon op dat moment",
 * en daar rekent de pagina zelf mee verder. Valt de wifi in de zaal weg, dan
 * loopt de klok gewoon door en klopt hij nog steeds.
 */

export interface ZaalBord {
  club_name: string
  primary_color: string | null
  tournament_id: string
  name: string
  status: string
  clock: string
  level_idx: number
  level_started_at: string | null
  level_elapsed_ms: number | string
  scheduled_at: string
  starting_stack: number
  late_reg_level: number | null
  entries: number
  players_left: number
  rebuys: number
  addons: number
  prize_pool_cents: number
  chips_in_play: number
  currency: string
  server_now: string
}

export interface ZaalLevel {
  idx: number
  is_break: boolean
  label: string | null
  small_blind: number
  big_blind: number
  ante: number
  duration_s: number
}

/** Tekst die in HTML belandt. Vier tekens, meer heeft dit niet nodig. */
export function esc(v: string): string {
  return v
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

/**
 * Een kleur die van buiten komt, voor ze in een stylesheet gaat.
 *
 * `primary_color` komt uit de database en wordt door een beheerder gezet. Dat
 * is geen vreemde, maar het is wel invoer, en invoer die rechtstreeks in een
 * `<style>` belandt hoort gecontroleerd te worden. Alleen een hexkleur komt
 * erdoor; al de rest valt terug op het goud van het platform.
 */
export function veiligeKleur(v: string | null | undefined, terugval: string): string {
  return typeof v === 'string' && /^#[0-9a-f]{3,8}$/i.test(v.trim()) ? v.trim() : terugval
}

/**
 * De pagina.
 *
 * Eén string, met de eerste stand er al in gerenderd. Dat is met opzet: een
 * tv die een seconde lang "laden…" toont terwijl de zaal kijkt, oogt stuk.
 * Het JavaScript neemt het daarna over.
 */
export function zaalHtml(opts: {
  sleutel: string
  bord: ZaalBord | null
  levels: ZaalLevel[]
  clubNaam: string
}): string {
  const { sleutel, bord, levels, clubNaam } = opts
  const accent = veiligeKleur(bord?.primary_color, '#c8a15c')

  // De begintoestand gaat als JSON mee in de pagina. JSON.stringify kan een
  // `</script>` opleveren als er ooit zo'n tekst in een tornooinaam staat;
  // vandaar het afbreken van die ene reeks.
  const data = JSON.stringify({ bord, levels }).replace(/</g, '\\u003c')

  return `<!doctype html>
<html lang="nl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(clubNaam)}</title>
<style>
  /* Alleen dingen die een browser van 2019 kent. Geen @layer, geen
     color-mix, geen oklch, geen dvh, geen container queries: precies de
     onderdelen waarop de gewone app het op een tv begeeft. */
  html, body {
    margin: 0;
    padding: 0;
    height: 100%;
    background: #07090c;
    color: #ffffff;
    font-family: Arial, Helvetica, sans-serif;
    overflow: hidden;
  }
  #blad {
    box-sizing: border-box;
    height: 100%;
    padding: 2.5vh 3vw;
    display: flex;
    flex-direction: column;
  }
  .kop {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  .club {
    font-size: 3.2vh;
    font-weight: bold;
    letter-spacing: 0.25vh;
    color: ${accent};
  }
  .avond { font-size: 2.6vh; color: #9aa3b2; }
  .midden {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
  }
  .tijd {
    font-size: 30vh;
    font-weight: bold;
    line-height: 0.95;
    letter-spacing: -1vh;
    font-variant-numeric: tabular-nums;
  }
  .tijd.break { color: ${accent}; }
  .levelnaam {
    font-size: 3vh;
    letter-spacing: 0.5vh;
    text-transform: uppercase;
    color: #9aa3b2;
    margin-bottom: 1vh;
  }
  .blinds { font-size: 7vh; font-weight: bold; margin-top: 1vh; }
  .hierna { font-size: 2.6vh; color: #6b7484; margin-top: 1.2vh; }
  .voet {
    display: flex;
    justify-content: space-between;
    border-top: 1px solid #1b2230;
    padding-top: 2vh;
  }
  .vak { text-align: center; flex: 1; }
  .vak .label {
    font-size: 1.6vh;
    letter-spacing: 0.25vh;
    text-transform: uppercase;
    color: #6b7484;
  }
  .vak .waarde {
    font-size: 4.2vh;
    font-weight: bold;
    font-variant-numeric: tabular-nums;
    margin-top: 0.4vh;
  }
  .vak .bb { font-size: 2.6vh; font-weight: bold; color: ${accent}; }
  .leeg { text-align: center; color: #6b7484; font-size: 4vh; }
  .oud { color: #fbbf24; font-size: 2vh; text-align: center; padding-top: 1vh; }
</style>
</head>
<body>
<div id="blad"><div class="leeg">…</div></div>
<script>
/* Bewust ouderwets geschreven: var, function, string-optelling. Geen pijlen,
   geen template literals, geen ?. — een Chromium 69 leest dit zonder morren. */
(function () {
  'use strict';
  var SLEUTEL = ${JSON.stringify(sleutel)};
  var start = ${data};
  var bord = start.bord;
  var levels = start.levels || [];
  /* Het verschil tussen de klok van deze tv en die van de server. Een tv die
     er twee minuten naast zit, telt anders twee minuten verkeerd af. */
  var verschil = 0;
  var laatsteFout = 0;

  function nu() { return Date.now() + verschil; }

  function getal(n) {
    var s = String(Math.round(n));
    var uit = '';
    while (s.length > 3) {
      uit = '.' + s.slice(-3) + uit;
      s = s.slice(0, -3);
    }
    return s + uit;
  }

  function tijd(ms) {
    var tot = Math.max(0, Math.round(ms / 1000));
    var u = Math.floor(tot / 3600);
    var m = Math.floor((tot % 3600) / 60);
    var s = tot % 60;
    var mm = m < 10 ? '0' + m : String(m);
    var ss = s < 10 ? '0' + s : String(s);
    return u > 0 ? u + ':' + mm + ':' + ss : mm + ':' + ss;
  }

  /* Dezelfde redenering als resolveClock in de app: vanaf het opgeslagen
     level en de opgebouwde tijd doorrollen tot we het level vinden waar we
     nu in zitten. Zo blijft de tv gelijklopen met het floorscherm, ook als
     niemand daar iets aangeraakt heeft. */
  function stand() {
    if (!bord || !levels.length) return null;
    var idx = bord.level_idx || 0;
    var over = Number(bord.level_elapsed_ms || 0);
    if (bord.clock === 'running' && bord.level_started_at) {
      over += nu() - Date.parse(bord.level_started_at);
    }
    while (idx < levels.length) {
      var duur = levels[idx].duration_s * 1000;
      if (over < duur) break;
      over -= duur;
      idx += 1;
    }
    if (idx >= levels.length) idx = levels.length - 1;
    var level = levels[idx];
    var rest = Math.max(0, level.duration_s * 1000 - over);
    /* Het nummer dat de zaal ziet telt pauzes niet mee: een break heeft een
       naam, geen nummer. Zelfde telling als op het floorscherm. */
    var nr = 0;
    for (var i = 0; i <= idx; i += 1) if (!levels[i].is_break) nr += 1;
    var totaal = 0;
    for (var j = 0; j < levels.length; j += 1) if (!levels[j].is_break) totaal += 1;
    return {
      level: level,
      volgende: levels[idx + 1] || null,
      rest: rest,
      nr: nr,
      totaal: totaal
    };
  }

  function blinds(l) {
    if (!l) return '—';
    if (l.is_break) return breakNaam(l);
    var t = getal(l.small_blind) + ' / ' + getal(l.big_blind);
    if (l.ante > 0) t += '  (ante ' + getal(l.ante) + ')';
    return t;
  }

  function breakNaam(l) {
    var v = (l.label || '').toLowerCase();
    if (v === '' || v === 'pauze' || v === 'pause' || v === 'break') return 'BREAK';
    return l.label;
  }

  function vak(label, waarde, bb) {
    return '<div class="vak"><div class="label">' + label + '</div>'
      + '<div class="waarde">' + waarde + '</div>'
      + (bb ? '<div class="bb">' + bb + '</div>' : '') + '</div>';
  }

  function geld(cent, munt) {
    var teken = munt === 'EUR' ? '\\u20ac ' : (munt + ' ');
    return teken + getal(cent / 100);
  }

  function teken() {
    var blad = document.getElementById('blad');
    if (!bord) {
      blad.innerHTML = '<div class="kop"><div class="club">'
        + document.title.toUpperCase() + '</div></div>'
        + '<div class="midden"><div class="leeg">Geen tornooi bezig</div></div>';
      return;
    }
    var s = stand();
    var h = '';
    h += '<div class="kop"><div class="club">' + esc(bord.club_name).toUpperCase() + '</div>'
      + '<div class="avond">' + esc(bord.name) + '</div></div>';

    h += '<div class="midden"><div>';
    if (s) {
      h += '<div class="levelnaam">'
        + (s.level.is_break ? breakNaam(s.level) : 'Level ' + s.nr + ' / ' + s.totaal)
        + '</div>';
      h += '<div class="tijd' + (s.level.is_break ? ' break' : '') + '">' + tijd(s.rest) + '</div>';
      h += '<div class="blinds">' + blinds(s.level) + '</div>';
      h += '<div class="hierna">'
        + (s.volgende ? 'Hierna: ' + blinds(s.volgende) : 'Laatste level') + '</div>';
    } else {
      h += '<div class="leeg">Nog geen structuur</div>';
    }
    h += '</div></div>';

    var gem = bord.players_left > 0
      ? Math.round(bord.chips_in_play / bord.players_left) : 0;
    var bb = (s && !s.level.is_break && s.level.big_blind > 0)
      ? Math.round(gem / s.level.big_blind) + ' bb' : '';

    h += '<div class="voet">'
      + vak('Spelers', bord.players_left + ' / ' + bord.entries, '')
      + vak('Gem. stack', getal(gem), bb)
      + vak('Inkopen', String(bord.entries + bord.rebuys), '')
      + vak('Prijzenpot', geld(bord.prize_pool_cents, bord.currency), '')
      + '</div>';

    if (laatsteFout && nu() - laatsteFout > 60000) {
      h += '<div class="oud">Geen verbinding met de server</div>';
    }
    blad.innerHTML = h;
  }

  function esc(v) {
    return String(v === null || v === undefined ? '' : v)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function haal() {
    var req = new XMLHttpRequest();
    /* Een adres dat met ? begint hangt aan de huidige pagina. Zo werkt het
       zowel op app.cutoff.be/zaal als op pokerleague.be/c/cutoff/zaal, zonder
       dat de pagina hoeft te weten waar ze staat. */
    req.open('GET', '?k=' + encodeURIComponent(SLEUTEL)
      + '&json=1&t=' + Date.now(), true);
    req.onreadystatechange = function () {
      if (req.readyState !== 4) return;
      if (req.status !== 200) { laatsteFout = Date.now(); return; }
      try {
        var d = JSON.parse(req.responseText);
        /* De servertijd komt mee, dus een tv met een verkeerd ingestelde klok
           telt toch juist af. */
        if (d.bord && d.bord.server_now) {
          verschil = Date.parse(d.bord.server_now) - Date.now();
        }
        var anderTornooi = (!bord && d.bord)
          || (bord && d.bord && bord.tournament_id !== d.bord.tournament_id);
        bord = d.bord;
        if (anderTornooi || !levels.length) levels = d.levels || [];
        laatsteFout = 0;
        teken();
      } catch (e) {
        laatsteFout = Date.now();
      }
    };
    req.send();
  }

  teken();
  setInterval(teken, 250);
  setInterval(haal, 10000);
  haal();
}());
</script>
</body>
</html>`
}
