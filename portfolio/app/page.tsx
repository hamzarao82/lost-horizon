import fs from "node:fs";
import path from "node:path";
import { asset, controls, doc, docLinks, features, RELEASE_URL, REPO_URL, stats } from "@/lib/site";

const REAL_IMAGE = /\.(png|jpe?g|webp|avif)$/i;

/** Real screenshots win; the placeholder SVGs only show until the first real image is dropped in. */
function loadScreens(): { src: string; caption: string; placeholder: boolean }[] {
  const dir = path.join(process.cwd(), "public", "screens");
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
  const real = files.filter((f) => REAL_IMAGE.test(f));
  const chosen = real.length > 0 ? real : files.filter((f) => /^placeholder.*\.svg$/i.test(f));
  return chosen.map((f) => ({
    src: asset(`/screens/${f}`),
    caption: f.replace(/\.[^.]+$/, "").replace(/^placeholder-?/i, "").replace(/^\d+[-_]*/, "").replace(/[-_]+/g, " ").trim() || "Screenshot",
    placeholder: real.length === 0,
  }));
}

const hasTrailer = fs.existsSync(path.join(process.cwd(), "public", "trailer.mp4"));

function Architecture() {
  return (
    <div className="diagram">
      <svg viewBox="0 0 900 410" role="img" aria-labelledby="arch-title arch-desc">
        <title id="arch-title">Lost Horizon architecture</title>
        <desc id="arch-desc">
          Boot loads the Main scene. Main contains the player, the wave director, arena decor and UI. Five autoloads
          provide audio, settings, saving, effects and teleport. The player and enemies share one hitbox damage pipeline.
        </desc>
        <defs>
          <marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0 0 10 5 0 10z" fill="#a3b0c2" />
          </marker>
        </defs>

        <rect className="box hot" x="20" y="20" width="130" height="50" rx="10" />
        <text x="85" y="42" textAnchor="middle">Boot</text>
        <text className="dim" x="85" y="59" textAnchor="middle">staged loading</text>
        <path className="arrow" d="M150 45H210" />

        <rect className="box hot" x="215" y="20" width="170" height="50" rx="10" />
        <text x="300" y="42" textAnchor="middle">Main scene</text>
        <text className="dim" x="300" y="59" textAnchor="middle">arena, player, UI</text>

        <rect className="box cool" x="470" y="20" width="410" height="66" rx="10" />
        <text x="486" y="42">Autoloads</text>
        <text className="dim" x="486" y="62">AudioManager · Settings · Fx · SaveManager · Teleport</text>
        <text className="dim" x="486" y="78">(each wires itself to the game through signals and node_added)</text>

        <path className="arrow" d="M300 70V104M85 104H835M300 104H300" />
        {[
          [20, "Player", "CharacterBody3D"],
          [170, "Arena decor", "built over frames"],
          [320, "HUD", "bars, toasts, boss bar"],
          [470, "Pause menu", "settings, save, load"],
          [620, "Touch controls", "stick, look, buttons"],
        ].map(([x, t, s]) => (
          <g key={String(t)}>
            <path className="arrow" d={`M${Number(x) + 65} 104V126`} />
            <rect className="box" x={Number(x)} y="128" width="130" height="50" rx="10" />
            <text x={Number(x) + 65} y="150" textAnchor="middle">{t}</text>
            <text className="dim" x={Number(x) + 65} y="167" textAnchor="middle">{s}</text>
          </g>
        ))}
        <path className="arrow" d="M835 104V126" />
        <rect className="box hot" x="770" y="128" width="110" height="50" rx="10" />
        <text x="825" y="150" textAnchor="middle">Wave director</text>
        <text className="dim" x="825" y="167" textAnchor="middle">5 waves</text>

        <rect x="10" y="205" width="560" height="195" rx="14" fill="none" stroke="#243247" strokeDasharray="5 5" />
        <text className="dim" x="24" y="225">Player subsystems</text>
        <path className="arrow" d="M85 178V205" />
        {[
          [24, 238, 160, "Input queue", "3 slots, events + touch"],
          [196, 238, 176, "Combat pipeline", "AttackData → Hitbox"],
          [384, 238, 170, "Health + Armor", "armor drains first"],
          [24, 312, 160, "Lock-on", "cone, LOS, cycling"],
          [196, 312, 176, "Inventory", "swords, armor, medkits"],
          [384, 312, 170, "Teleport", "2 charges, 10 min"],
        ].map(([x, y, w, t, s]) => (
          <g key={String(t)}>
            <rect className="box" x={Number(x)} y={Number(y)} width={Number(w)} height="58" rx="10" />
            <text x={Number(x) + Number(w) / 2} y={Number(y) + 24} textAnchor="middle">{t}</text>
            <text className="dim" x={Number(x) + Number(w) / 2} y={Number(y) + 42} textAnchor="middle">{s}</text>
          </g>
        ))}

        <rect x="640" y="205" width="250" height="195" rx="14" fill="none" stroke="#243247" strokeDasharray="5 5" />
        <text className="dim" x="654" y="225">Enemies</text>
        <path className="arrow" d="M825 178V205" />
        {[
          [654, 238, "Soldier · Heavy · Hunter", "chase, ring, token attack"],
          [654, 312, "The Warden", "2 phases, shockwave, summons"],
        ].map(([x, y, t, s]) => (
          <g key={String(t)}>
            <rect className="box" x={Number(x)} y={Number(y)} width="222" height="58" rx="10" />
            <text x={Number(x) + 111} y={Number(y) + 24} textAnchor="middle">{t}</text>
            <text className="dim" x={Number(x) + 111} y={Number(y) + 42} textAnchor="middle">{s}</text>
          </g>
        ))}
        <path className="arrow" d="M640 270H574" />
        <text className="dim" x="607" y="262" textAnchor="middle">same</text>
        <text className="dim" x="607" y="294" textAnchor="middle">hitbox</text>
      </svg>
    </div>
  );
}

export default function Home() {
  const screens = loadScreens();
  return (
    <>
      <a className="skip" href="#main">Skip to content</a>
      <header className="top">
        <div className="wrap">
          <strong>LOST HORIZON</strong>
          <nav aria-label="Sections">
            <a href="#features">Features</a>
            <a href="#screens">Screens</a>
            <a href="#controls">Controls</a>
            <a href="#tech">Tech</a>
            <a href="#download">Download</a>
            <a href={REPO_URL}>GitHub</a>
          </nav>
        </div>
      </header>

      <main id="main">
        <div className="hero">
          <div className="wrap">
            <p className="eyebrow">Third-person action-adventure · Godot 4</p>
            <h1>Lost Horizon: <span>Black Site</span></h1>
            <p className="lead">
              You wake on a beach with no memory and no weapon. Fight through patrols on an island run by a secret
              military experiment, find better gear, and take down its warden. A solo-built action game that runs
              in your browser, on Windows and on Android.
            </p>
            <div className="actions">
              <a className="btn primary" href={asset("/play/")}>Play in browser</a>
              <a className="btn" href="#download">Download</a>
              <a className="btn" href={REPO_URL}>Source on GitHub</a>
            </div>
            <p className="note">
              Work in progress: the playable build is a combat arena with five waves and a boss. The island, story
              and quests come next. See the <a href={doc("COMBAT.md")}>combat notes</a> and the roadmap in the README.
            </p>
          </div>
        </div>

        <section id="features">
          <div className="wrap">
            <h2>What is in the build</h2>
            <p className="sub">Everything below is implemented and covered by headless tests.</p>
            <div className="grid">
              {features.map((f) => (
                <article className="card" key={f.title}>
                  <h3>{f.title}</h3>
                  <p>{f.text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="screens">
          <div className="wrap">
            <h2>Screens</h2>
            <p className="sub">
              {screens.length > 0 && screens[0].placeholder
                ? "Placeholder images. Real screenshots appear here once they are added to portfolio/public/screens."
                : "Captured from the running game."}
            </p>
            <ul className="gallery">
              {screens.map((s) => (
                <li key={s.src}>
                  <figure style={{ margin: 0 }}>
                    <img src={s.src} alt={s.placeholder ? "Placeholder for a gameplay screenshot" : s.caption} loading="lazy" width={1280} height={720} />
                    <figcaption>{s.caption}</figcaption>
                  </figure>
                </li>
              ))}
            </ul>
          </div>
        </section>

        {hasTrailer && (
          <section id="trailer">
            <div className="wrap">
              <h2>Trailer</h2>
              <video controls preload="none" playsInline>
                <source src={asset("/trailer.mp4")} type="video/mp4" />
              </video>
            </div>
          </section>
        )}

        <section id="controls">
          <div className="wrap">
            <h2>Controls</h2>
            <p className="sub">
              Keyboard and mouse are fully supported. On phones the on-screen controls appear automatically. The
              gamepad covers the special, lock-on, target switching, teleport and pause; movement and attack
              bindings for gamepads are not in yet.
            </p>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th scope="col">Action</th><th scope="col">Keyboard and mouse</th><th scope="col">Gamepad</th><th scope="col">Touch</th></tr>
                </thead>
                <tbody>
                  {controls.map(([action, kb, pad, touch]) => (
                    <tr key={action}>
                      <td>{action}</td>
                      <td><kbd>{kb}</kbd></td>
                      <td>{pad}</td>
                      <td>{touch}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section id="tech">
          <div className="wrap">
            <h2>Under the hood</h2>
            <p className="sub">
              Godot 4.7, typed GDScript and the Compatibility renderer, so one codebase runs on desktop, mobile and
              the web. Items, attacks, loot and quests are data (Godot Resources), not hard-coded.
            </p>
            <div className="stats">
              {stats.map((s) => (
                <div className="stat" key={s.label}>
                  <b>{s.value}</b><small>{s.unit}</small>
                  <p>{s.label}</p>
                </div>
              ))}
            </div>
            <p className="note" style={{ marginTop: 0, marginBottom: 24 }}>
              Frame rates were measured on Windows. The web build and the Android APK are produced by the same
              project but have not been benchmarked on hardware yet. Full numbers:{" "}
              <a href={doc("PERFORMANCE.md")}>PERFORMANCE.md</a>.
            </p>
            <Architecture />
          </div>
        </section>

        <section id="download">
          <div className="wrap">
            <h2>Play and download</h2>
            <p className="sub">The browser version needs nothing installed. The first load downloads about 10 MB.</p>
            <div className="dl">
              <article className="card">
                <h3>Browser</h3>
                <p>Desktop or phone. Runs the same build with touch controls on mobile.</p>
                <a className="btn primary" href={asset("/play/")}>Play now</a>
              </article>
              <article className="card">
                <h3>Windows</h3>
                <p>64-bit zip. Extract and run LostHorizon.exe. Unsigned, so SmartScreen may warn.</p>
                <a className="btn" href={`${RELEASE_URL}/LostHorizon-windows.zip`}>Download .zip</a>
              </article>
              <article className="card">
                <h3>Android</h3>
                <p>Debug-signed arm64 APK. Allow installs from your browser to sideload it.</p>
                <a className="btn" href={`${RELEASE_URL}/LostHorizon-android.apk`}>Download .apk</a>
              </article>
            </div>
          </div>
        </section>

        <section id="docs" style={{ borderBottom: 0 }}>
          <div className="wrap">
            <h2>Documentation</h2>
            <ul className="links">
              {docLinks.map(([label, file]) => (
                <li key={file}><a href={doc(file)}>{label}</a></li>
              ))}
              <li><a href={`${REPO_URL}/releases`}>Releases</a></li>
            </ul>
          </div>
        </section>
      </main>

      <footer>
        <div className="wrap">
          <p>Lost Horizon: Black Site by Hamza Rao. Code under the MIT licence.</p>
          <p>All audio is generated by script and there are no third-party assets. No analytics or trackers on this site.</p>
        </div>
      </footer>
    </>
  );
}
