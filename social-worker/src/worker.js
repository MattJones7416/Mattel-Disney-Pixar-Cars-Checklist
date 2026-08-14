var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/worker.js
var encoder = new TextEncoder();
var decoder = new TextDecoder();
var DEFAULT_BLOCKED_TERMS = [
  "abuse",
  "bully",
  "harass",
  "hate crime",
  "kill yourself",
  "kys",
  "nazi",
  "kkk",
  "retard",
  "nonce",
  "paedo",
  "pedo",
  "porn",
  "sex",
  "nude",
  "nudes",
  "onlyfans",
  "fuck",
  "fucker",
  "shit",
  "cunt",
  "bitch",
  "bastard",
  "dick",
  "scam",
  "scammer",
  "crypto giveaway",
  "telegram",
  "whatsapp me",
  "buy followers"
];
var CATALOG_ALLOWED_TYPES = [
  "1:55 Die-Cast",
  "Mini Racers",
  "Collector Exclusive",
  "Special Edition",
  "Premium / Larger Scale"
];
var CATALOG_ALLOWED_STATUS = ["", "Coming Soon", "Exclusive", "Retired"];
var CATALOG_SOURCE_KEYS = [
  "checked",
  "built",
  "name",
  "number",
  "productCode",
  "action",
  "originalNumber",
  "character",
  "difficulty",
  "firstReleaseYear",
  "sheets",
  "releaseCount",
  "link",
  "category",
  "type",
  "status",
  "series",
  "releaseDate",
  "instructionsLink",
  "360View",
  "description",
  "productimage",
  "source",
  "sourceLicense"
];
var PRIVACY_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Mattel Disney Pixar Cars Checklist Privacy Policy</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; }
    body { max-width: 760px; margin: 0 auto; padding: 28px; }
    h1 { font-size: 28px; line-height: 1.2; }
    h2 { font-size: 18px; margin-top: 28px; }
    a { color: #d92d20; font-weight: 650; }
  </style>
</head>
<body>
  <h1>Mattel Disney Pixar Cars Checklist Privacy Policy</h1>
  <p>Last updated: 14 August 2026</p>
  <p>The app stores your checklist, notes, and local photos on your device. If you use the Community feed, we collect the account and post information needed to run that service.</p>
  <h2>Community account data</h2>
  <p>When you create a Community account, we store your display name, email address, account ID, password hash, account status, and community-rules acceptance timestamp. We do not store your password in plain text.</p>
  <h2>Community content</h2>
  <p>Messages, collection stats, deal links, reports, blocks, and uploaded photos are stored so they can be shown in the feed, moderated, reported, blocked, deleted, or removed by an admin.</p>
  <h2>Notifications</h2>
  <p>If you enable Community notifications, we store your device push token so we can send alerts about new Community posts and admin moderation items. You can disable notifications in iOS Settings, sign out, or delete your Community account.</p>
  <h2>Moderation and safety</h2>
  <p>Community posts may be filtered, reported, held for review, removed, or linked to account enforcement actions. Photo posts require admin approval before appearing in the public feed.</p>
  <h2>Security</h2>
  <p>For abuse prevention, the service stores short-lived rate-limit counters. Network addresses are transformed with a secret one-way signature before those counters are stored.</p>
  <h2>Deletion</h2>
  <p>You can delete your Community account in the app from Settings. This removes your Community account and your Community posts/photos. It does not delete your local checklist data.</p>
  <h2>Contact</h2>
  <p><a href="mailto:info@stonebrookstudios.co.uk">Contact Support</a></p>
</body>
</html>`;
var ADMIN_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pixar Cars Community Admin</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #f5f6f8; color: #16171a; }
    main { max-width: 1040px; margin: 0 auto; padding: 24px; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 20px; }
    h1 { font-size: 24px; margin: 0; }
    section, article { background: white; border: 1px solid rgba(0,0,0,.08); border-radius: 10px; padding: 16px; margin: 12px 0; }
    input, select, textarea, button { font: inherit; }
    input, select, textarea { width: 100%; box-sizing: border-box; padding: 10px; border: 1px solid rgba(0,0,0,.18); border-radius: 8px; background: transparent; }
    textarea { min-height: 80px; }
    button { border: 0; border-radius: 8px; padding: 9px 12px; background: #d92d20; color: white; cursor: pointer; }
    button.secondary { background: #63666d; }
    button.danger { background: #c43d3d; }
    button:disabled { opacity: .55; cursor: not-allowed; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
    .row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
    .muted { color: #6a6d75; font-size: 13px; }
    .pill { display: inline-flex; align-items: center; border-radius: 999px; padding: 4px 8px; background: rgba(217,45,32,.14); font-size: 12px; font-weight: 650; }
    .post img { max-width: 240px; border-radius: 8px; display: block; margin-top: 10px; }
    @media (prefers-color-scheme: dark) {
      body { background: #111318; color: #f5f6f8; }
      section, article { background: #1c1f26; border-color: rgba(255,255,255,.08); }
      input, select, textarea { border-color: rgba(255,255,255,.16); color: inherit; }
      .muted { color: #a5a9b3; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Pixar Cars Community Admin</h1>
      <button class="secondary" id="logout">Sign out</button>
    </header>

    <section id="auth">
      <h2>Admin Login</h2>
      <div class="grid">
        <input id="email" type="email" placeholder="Email">
        <input id="password" type="password" placeholder="Password">
      </div>
      <p class="muted">Create your first account from the app or use the register endpoint, then log in here with the admin email from wrangler.jsonc.</p>
      <button id="login">Log in</button>
    </section>

    <section>
      <div class="row">
        <select id="status">
          <option value="pending">Pending</option>
          <option value="approved">Approved</option>
          <option value="rejected">Rejected</option>
          <option value="all">All</option>
        </select>
        <button id="refresh">Refresh</button>
      </div>
      <div id="output"></div>
    </section>

    <section>
      <h2>Users</h2>
      <button id="refreshUsers">Refresh users</button>
      <div id="users"></div>
    </section>
  </main>
  <script>
    const $ = (id) => document.getElementById(id);
    let token = localStorage.getItem("pixar_cars_social_admin_token") || "";

    function headers() {
      return token ? { "Authorization": "Bearer " + token, "Content-Type": "application/json" } : { "Content-Type": "application/json" };
    }

    async function api(path, options = {}) {
      const res = await fetch(path, { ...options, headers: { ...headers(), ...(options.headers || {}) } });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || "Request failed");
      return data;
    }

    $("login").onclick = async () => {
      try {
        const data = await api("/v1/auth/login", {
          method: "POST",
          body: JSON.stringify({ email: $("email").value, password: $("password").value })
        });
        token = data.token;
        localStorage.setItem("pixar_cars_social_admin_token", token);
        await refresh();
        await refreshUsers();
      } catch (err) { alert(err.message); }
    };

    $("logout").onclick = () => {
      token = "";
      localStorage.removeItem("pixar_cars_social_admin_token");
      $("output").innerHTML = "";
      $("users").innerHTML = "";
    };

    $("refresh").onclick = refresh;
    $("refreshUsers").onclick = refreshUsers;
    $("status").onchange = refresh;

    async function refresh() {
      if (!token) return;
      const data = await api("/v1/admin/posts?status=" + encodeURIComponent($("status").value));
      $("output").innerHTML = data.posts.map(post => renderPost(post)).join("") || "<p class='muted'>No posts.</p>";
      document.querySelectorAll("[data-status]").forEach(button => {
        button.onclick = async () => {
          await api("/v1/admin/posts/" + button.dataset.id, {
            method: "PATCH",
            body: JSON.stringify({ status: button.dataset.status })
          });
          refresh();
        };
      });
      document.querySelectorAll("[data-delete]").forEach(button => {
        button.onclick = async () => {
          if (!confirm("Delete this post?")) return;
          await api("/v1/admin/posts/" + button.dataset.delete, { method: "DELETE" });
          refresh();
        };
      });
    }

    function escapeHTML(value) {
      return String(value || "").replace(/[&<>"']/g, ch => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[ch]));
    }

    function renderPost(post) {
      const image = post.imageUrl ? "<img src='" + post.imageUrl + "' alt='post image'>" : "";
      return "<article class='post'>" +
        "<div class='row'><strong>" + escapeHTML(post.authorName) + "</strong><span class='pill'>" + escapeHTML(post.status) + "</span><span class='muted'>" + escapeHTML(post.createdAt) + "</span></div>" +
        "<p>" + escapeHTML(post.message) + "</p>" + image +
        "<p class='muted'>Reports: " + post.reportCount + (post.moderationReason ? " - " + escapeHTML(post.moderationReason) : "") + "</p>" +
        "<div class='row'>" +
          "<button data-status='approved' data-id='" + post.id + "'>Approve</button>" +
          "<button class='secondary' data-status='pending' data-id='" + post.id + "'>Hold</button>" +
          "<button class='danger' data-status='rejected' data-id='" + post.id + "'>Reject</button>" +
          "<button class='danger' data-delete='" + post.id + "'>Delete</button>" +
        "</div>" +
      "</article>";
    }

    async function refreshUsers() {
      if (!token) return;
      const data = await api("/v1/admin/users");
      $("users").innerHTML = data.users.map(user => {
        const next = user.status === "active" ? "suspended" : "active";
        const label = user.status === "active" ? "Suspend" : "Reactivate";
        return "<article><div class='row'><strong>" + escapeHTML(user.username) + "</strong><span class='muted'>" + escapeHTML(user.email) + "</span><span class='pill'>" + escapeHTML(user.status) + "</span><span class='pill'>" + escapeHTML(user.role) + "</span><button class='secondary' data-user='" + user.id + "' data-next='" + next + "'>" + label + "</button></div></article>";
      }).join("") || "<p class='muted'>No users.</p>";
      document.querySelectorAll("[data-user]").forEach(button => {
        button.onclick = async () => {
          await api("/v1/admin/users/" + button.dataset.user, {
            method: "PATCH",
            body: JSON.stringify({ status: button.dataset.next })
          });
          refreshUsers();
        };
      });
    }

    if (token) { refresh(); refreshUsers(); }
  <\/script>
</body>
</html>`;
var worker_default = {
  async fetch(request, env, ctx) {
    try {
      if (request.method === "OPTIONS") {
        return withCors(new Response(null, { status: 204 }), request, env);
      }
      const url = new URL(request.url);
      const route = routeRequest(request.method, url.pathname);
      if (url.pathname === "/" || url.pathname === "/admin") {
        return html(ADMIN_HTML, request, env);
      }
      if (url.pathname === "/privacy") {
        return html(PRIVACY_HTML, request, env);
      }
      if (url.pathname === "/health") {
        return json({ ok: true, service: "pixar-cars-social-api", time: (/* @__PURE__ */ new Date()).toISOString() }, 200, request, env);
      }
      if (!route) {
        return json({ error: "Not found" }, 404, request, env);
      }
      if (route.name === "register") return register(request, env);
      if (route.name === "login") return login(request, env);
      if (route.name === "me") return me(request, env);
      if (route.name === "deleteAccount") return deleteAccount(request, env);
      if (route.name === "acceptRules") return acceptRules(request, env);
      if (route.name === "communityUsers") return communityUsers(request, env);
      if (route.name === "requestFriend") return updateFriendship(request, env, route.params.id, true);
      if (route.name === "removeFriend") return updateFriendship(request, env, route.params.id, false);
      if (route.name === "updateCollectionPrivacy") return updateCollectionPrivacy(request, env);
      if (route.name === "publishCollection") return publishCollection(request, env);
      if (route.name === "userCollection") return userCollection(request, env, route.params.id);
      if (route.name === "feed") return feed(request, env, ctx);
      if (route.name === "registerPushToken") return registerPushToken(request, env, ctx);
      if (route.name === "unregisterPushToken") return unregisterPushToken(request, env, route.params.token);
      if (route.name === "createPost") return createPost(request, env, ctx);
      if (route.name === "image") return image(request, env, route.params.id);
      if (route.name === "deletePost") return deletePost(request, env, route.params.id);
      if (route.name === "report") return report(request, env, route.params.id, ctx);
      if (route.name === "blockUser") return blockUser(request, env, route.params.id, true);
      if (route.name === "unblockUser") return blockUser(request, env, route.params.id, false);
      if (route.name === "adminPosts") return adminPosts(request, env, url);
      if (route.name === "adminReports") return adminReports(request, env, url);
      if (route.name === "adminUpdatePost") return adminUpdatePost(request, env, route.params.id, url, ctx);
      if (route.name === "adminDeletePost") return adminDeletePost(request, env, route.params.id);
      if (route.name === "adminUsers") return adminUsers(request, env);
      if (route.name === "adminUpdateUser") return adminUpdateUser(request, env, route.params.id);
      if (route.name === "updateCatalogModel") return updateCatalogModel(request, env);
      return json({ error: "Not found" }, 404, request, env);
    } catch (error) {
      if (error instanceof Response) {
        return withCors(error, request, env);
      }
      console.error(error);
      return json({ error: "Server error" }, 500, request, env);
    }
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(processPushNotificationJobs(env, numberEnv(env, "MAX_PUSH_RECIPIENTS_PER_EVENT", 40)));
  }
};
function routeRequest(method, pathname) {
  const exact = `${method} ${pathname}`;
  if (exact === "POST /v1/auth/register") return { name: "register", params: {} };
  if (exact === "POST /v1/auth/login") return { name: "login", params: {} };
  if (exact === "GET /v1/me") return { name: "me", params: {} };
  if (exact === "DELETE /v1/me") return { name: "deleteAccount", params: {} };
  if (exact === "POST /v1/me/accept-rules") return { name: "acceptRules", params: {} };
  if (exact === "GET /v1/users") return { name: "communityUsers", params: {} };
  if (exact === "PATCH /v1/me/privacy") return { name: "updateCollectionPrivacy", params: {} };
  if (exact === "PUT /v1/me/collection") return { name: "publishCollection", params: {} };
  if (exact === "POST /v1/push/register") return { name: "registerPushToken", params: {} };
  if (exact === "GET /v1/feed") return { name: "feed", params: {} };
  if (exact === "POST /v1/posts") return { name: "createPost", params: {} };
  if (exact === "GET /v1/admin/posts") return { name: "adminPosts", params: {} };
  if (exact === "GET /v1/admin/reports") return { name: "adminReports", params: {} };
  if (exact === "GET /v1/admin/users") return { name: "adminUsers", params: {} };
  if (exact === "POST /v1/catalog/models") return { name: "updateCatalogModel", params: {} };
  if (exact === "POST /v1/admin/catalog/models") return { name: "updateCatalogModel", params: {} };
  let match = pathname.match(/^\/v1\/posts\/([^/]+)\/image$/);
  if (method === "GET" && match) return { name: "image", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/posts\/([^/]+)\/report$/);
  if (method === "POST" && match) return { name: "report", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/posts\/([^/]+)$/);
  if (method === "DELETE" && match) return { name: "deletePost", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/push\/tokens\/([a-f0-9]+)$/i);
  if (method === "DELETE" && match) return { name: "unregisterPushToken", params: { token: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/users\/([^/]+)\/block$/);
  if (method === "POST" && match) return { name: "blockUser", params: { id: normalizedResourceID(match[1]) } };
  if (method === "DELETE" && match) return { name: "unblockUser", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/users\/([^/]+)\/friend$/);
  if (method === "POST" && match) return { name: "requestFriend", params: { id: normalizedResourceID(match[1]) } };
  if (method === "DELETE" && match) return { name: "removeFriend", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/users\/([^/]+)\/collection$/);
  if (method === "GET" && match) return { name: "userCollection", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/admin\/posts\/([^/]+)$/);
  if (method === "PATCH" && match) return { name: "adminUpdatePost", params: { id: normalizedResourceID(match[1]) } };
  if (method === "DELETE" && match) return { name: "adminDeletePost", params: { id: normalizedResourceID(match[1]) } };
  match = pathname.match(/^\/v1\/admin\/users\/([^/]+)$/);
  if (method === "PATCH" && match) return { name: "adminUpdateUser", params: { id: normalizedResourceID(match[1]) } };
  return null;
}
__name(routeRequest, "routeRequest");
function normalizedResourceID(value) {
  return String(value || "").trim().toLowerCase();
}
__name(normalizedResourceID, "normalizedResourceID");
async function register(request, env) {
  await consumeRateLimit(env, `auth:${await hashedClientIP(request, env)}`, numberEnv(env, "AUTH_ATTEMPTS_PER_HOUR", 12), 3600);
  const body = await readJSON(request);
  const username = cleanText(body.username, 32);
  const email = cleanText(body.email, 254).toLowerCase();
  const password = String(body.password || "");
  const acceptedRules = body.acceptedRules === true || body.communityGuidelinesAccepted === true;
  if (!username || !email.includes("@") || password.length < 8) {
    return json({ error: "Use a username, valid email, and password of at least 8 characters." }, 400, request, env);
  }
  if (!acceptedRules) {
    return json({ error: "Accept the community rules before creating an account." }, 403, request, env);
  }
  const existing = await env.DB.prepare("SELECT id FROM users WHERE email_norm = ? OR username_norm = ?").bind(email, normalizeUsername(username)).first();
  if (existing) {
    return json({ error: "That email or username is already registered." }, 409, request, env);
  }
  const id = crypto.randomUUID();
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const salt = randomBase64URL(16);
  const passwordHash = await hashPassword(password, salt, env);
  const role = email === String(env.ADMIN_EMAIL || "").trim().toLowerCase() ? "admin" : "user";
  await env.DB.prepare(`
    INSERT INTO users (id, username, username_norm, email, email_norm, password_hash, password_salt, role, status, created_at, updated_at, rules_accepted_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?)
  `).bind(id, username, normalizeUsername(username), email, email, passwordHash, salt, role, now, now, now).run();
  const token = await createToken({ sub: id, email, role }, env);
  return json({ token, user: { id, username, email, role, status: "active", createdAt: now, rulesAcceptedAt: now } }, 201, request, env);
}
__name(register, "register");
async function login(request, env) {
  await consumeRateLimit(env, `auth:${await hashedClientIP(request, env)}`, numberEnv(env, "AUTH_ATTEMPTS_PER_HOUR", 12), 3600);
  const body = await readJSON(request);
  const email = cleanText(body.email, 254).toLowerCase();
  const password = String(body.password || "");
  const user = await env.DB.prepare("SELECT * FROM users WHERE email_norm = ?").bind(email).first();
  if (!user || user.status !== "active") {
    return json({ error: "Email or password not recognised." }, 401, request, env);
  }
  const candidateHash = await hashPassword(password, user.password_salt, env);
  if (!timingSafeEqual(candidateHash, user.password_hash)) {
    return json({ error: "Email or password not recognised." }, 401, request, env);
  }
  const token = await createToken({ sub: user.id, email: user.email_norm, role: user.role }, env);
  return json({ token, user: publicUser(user) }, 200, request, env);
}
__name(login, "login");
async function me(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  return json({ user: publicUser(auth.user) }, 200, request, env);
}
__name(me, "me");
async function deleteAccount(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const postRows = await env.DB.prepare("SELECT id, image_key, image_bytes FROM posts WHERE author_id = ?").bind(auth.user.id).all();
  let removedBytes = 0;
  for (const post of postRows.results || []) {
    if (post.image_key) {
      await env.MEDIA.delete(post.image_key);
      removedBytes += Number(post.image_bytes || 0);
    }
  }
  const postIDs = (postRows.results || []).map((post) => post.id);
  for (const postID of postIDs) {
    await env.DB.prepare("DELETE FROM reports WHERE post_id = ?").bind(postID).run();
  }
  await env.DB.prepare("DELETE FROM reports WHERE reporter_id = ?").bind(auth.user.id).run();
  await env.DB.prepare("DELETE FROM user_blocks WHERE blocker_id = ? OR blocked_id = ?").bind(auth.user.id, auth.user.id).run();
  await env.DB.prepare("DELETE FROM friendships WHERE requester_id = ? OR addressee_id = ?").bind(auth.user.id, auth.user.id).run();
  await env.DB.prepare("DELETE FROM collection_snapshots WHERE user_id = ?").bind(auth.user.id).run();
  await env.DB.prepare("DELETE FROM push_tokens WHERE user_id = ?").bind(auth.user.id).run();
  await env.DB.prepare("DELETE FROM posts WHERE author_id = ?").bind(auth.user.id).run();
  await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(auth.user.id).run();
  if (removedBytes > 0) {
    await setMediaBytes(env, Math.max(0, await currentMediaBytes(env) - removedBytes));
  }
  return json({ ok: true }, 200, request, env);
}
__name(deleteAccount, "deleteAccount");
async function acceptRules(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare("UPDATE users SET rules_accepted_at = ?, updated_at = ? WHERE id = ?").bind(now, now, auth.user.id).run();
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(auth.user.id).first();
  return json({ user: publicUser(user) }, 200, request, env);
}
__name(acceptRules, "acceptRules");
async function communityUsers(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const rows = await env.DB.prepare(`
    SELECT
      u.id,
      u.username,
      u.role,
      u.status,
      u.created_at,
      u.rules_accepted_at,
      COALESCE(u.collection_visibility, 'friends') AS collection_visibility,
      s.updated_at AS collection_updated_at,
      s.model_count AS collection_model_count
    FROM users u
    LEFT JOIN collection_snapshots s ON s.user_id = u.id
    WHERE u.status = 'active'
    ORDER BY lower(u.username) ASC
    LIMIT 500
  `).all();
  const friendships = await friendshipsForUser(env, auth.user.id);
  return json({
    users: (rows.results || []).map((row) => publicCommunityUser(row, auth.user.id, friendshipStatusForUser(row.id, auth.user.id, friendships)))
  }, 200, request, env);
}
__name(communityUsers, "communityUsers");
async function updateFriendship(request, env, targetID, shouldRequest) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (targetID === auth.user.id) {
    return json({ error: "You cannot friend yourself." }, 400, request, env);
  }
  const target = await env.DB.prepare("SELECT id, username, role, status, created_at, rules_accepted_at, COALESCE(collection_visibility, 'friends') AS collection_visibility FROM users WHERE id = ? AND status = 'active'").bind(targetID).first();
  if (!target) return json({ error: "User not found." }, 404, request, env);
  const existing = await friendshipBetween(env, auth.user.id, targetID);
  const now = (/* @__PURE__ */ new Date()).toISOString();
  if (!shouldRequest) {
    if (existing) {
      await env.DB.prepare("DELETE FROM friendships WHERE requester_id = ? AND addressee_id = ?").bind(existing.requester_id, existing.addressee_id).run();
    }
    return json({ ok: true, user: publicCommunityUser(target, auth.user.id, "none") }, 200, request, env);
  }
  if (!existing) {
    await env.DB.prepare("INSERT INTO friendships (requester_id, addressee_id, status, created_at, updated_at) VALUES (?, ?, 'pending', ?, ?)").bind(auth.user.id, targetID, now, now).run();
    return json({ ok: true, user: publicCommunityUser(target, auth.user.id, "requested") }, 200, request, env);
  }
  if (existing.status === "accepted") {
    return json({ ok: true, user: publicCommunityUser(target, auth.user.id, "friends") }, 200, request, env);
  }
  if (existing.addressee_id === auth.user.id) {
    await env.DB.prepare("UPDATE friendships SET status = 'accepted', updated_at = ? WHERE requester_id = ? AND addressee_id = ?").bind(now, existing.requester_id, existing.addressee_id).run();
    return json({ ok: true, user: publicCommunityUser(target, auth.user.id, "friends") }, 200, request, env);
  }
  return json({ ok: true, user: publicCommunityUser(target, auth.user.id, "requested") }, 200, request, env);
}
__name(updateFriendship, "updateFriendship");
async function updateCollectionPrivacy(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJSON(request);
  const visibility = allowedCollectionVisibility(body.collectionVisibility || body.visibility);
  if (!visibility) return json({ error: "Collection visibility must be friends, everyone, or none." }, 400, request, env);
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare("UPDATE users SET collection_visibility = ?, updated_at = ? WHERE id = ?").bind(visibility, now, auth.user.id).run();
  await env.DB.prepare("UPDATE collection_snapshots SET visibility = ?, updated_at = ? WHERE user_id = ?").bind(visibility, now, auth.user.id).run();
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(auth.user.id).first();
  return json({ ok: true, user: publicUser(user) }, 200, request, env);
}
__name(updateCollectionPrivacy, "updateCollectionPrivacy");
async function publishCollection(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJSON(request);
  const models = sanitizeCollectionModels(body.models);
  const stats = sanitizeStatsObject(body.stats);
  const visibility = allowedCollectionVisibility(auth.user.collection_visibility) || "friends";
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare(`
    INSERT INTO collection_snapshots (user_id, visibility, stats_json, models_json, model_count, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET
      visibility = excluded.visibility,
      stats_json = excluded.stats_json,
      models_json = excluded.models_json,
      model_count = excluded.model_count,
      updated_at = excluded.updated_at
  `).bind(auth.user.id, visibility, JSON.stringify(stats), JSON.stringify(models), models.length, now).run();
  return json({ ok: true, updatedAt: now, modelCount: models.length }, 200, request, env);
}
__name(publishCollection, "publishCollection");
async function userCollection(request, env, targetID) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const target = await env.DB.prepare(`
    SELECT
      u.id,
      u.username,
      u.role,
      u.status,
      u.created_at,
      u.rules_accepted_at,
      COALESCE(u.collection_visibility, 'friends') AS collection_visibility,
      s.updated_at AS collection_updated_at,
      s.model_count AS collection_model_count
    FROM users u
    LEFT JOIN collection_snapshots s ON s.user_id = u.id
    WHERE u.id = ? AND u.status = 'active'
  `).bind(targetID).first();
  if (!target) return json({ error: "User not found." }, 404, request, env);
  const friendship = targetID === auth.user.id ? null : await friendshipBetween(env, auth.user.id, targetID);
  const relationship = friendshipStatusForUser(targetID, auth.user.id, friendship ? [friendship] : []);
  if (!canViewCollection(target, relationship, auth.user.id)) {
    return json({ error: "That collection is private." }, 403, request, env);
  }
  const snapshot = await env.DB.prepare("SELECT visibility, stats_json, models_json, model_count, updated_at FROM collection_snapshots WHERE user_id = ?").bind(targetID).first();
  if (!snapshot) {
    return json({
      user: publicCommunityUser(target, auth.user.id, relationship),
      collection: { models: [], stats: sanitizeStatsObject({}), updatedAt: "", visibility: allowedCollectionVisibility(target.collection_visibility) || "friends" }
    }, 200, request, env);
  }
  return json({
    user: publicCommunityUser(target, auth.user.id, relationship),
    collection: {
      models: safeJSON(snapshot.models_json, []),
      stats: sanitizeStatsObject(safeJSON(snapshot.stats_json, {})),
      updatedAt: snapshot.updated_at || "",
      visibility: allowedCollectionVisibility(snapshot.visibility) || "friends"
    }
  }, 200, request, env);
}
__name(userCollection, "userCollection");
async function feed(request, env, ctx) {
  const url = new URL(request.url);
  const limit = Math.min(
    Math.max(parseInt(url.searchParams.get("limit") || "40", 10) || 40, 1),
    numberEnv(env, "MAX_FEED_LIMIT", 60)
  );
  const before = url.searchParams.get("before") || "";
  const viewer = await optionalUser(request, env);
  const cacheKey = new Request(`${url.origin}/v1/feed?limit=${limit}&before=${encodeURIComponent(before)}`, request);
  const cache = caches.default;
  const cached = viewer ? null : await cache.match(cacheKey);
  if (cached) {
    return withCors(cached, request, env);
  }
  let rows;
  if (before && viewer) {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        WHERE (p.status = 'approved' OR (p.author_id = ? AND p.status = 'pending'))
          AND p.created_at < ?
          AND (? = 'admin' OR p.author_id NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?))
        ORDER BY p.created_at DESC LIMIT ?
      `).bind(viewer.id, before, viewer.role, viewer.id, limit).all();
  } else if (before) {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        WHERE p.status = 'approved' AND p.created_at < ?
        ORDER BY p.created_at DESC LIMIT ?
      `).bind(before, limit).all();
  } else if (viewer) {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        WHERE (p.status = 'approved' OR (p.author_id = ? AND p.status = 'pending'))
          AND (? = 'admin' OR p.author_id NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?))
        ORDER BY p.created_at DESC LIMIT ?
      `).bind(viewer.id, viewer.role, viewer.id, limit).all();
  } else {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        WHERE p.status = 'approved'
        ORDER BY p.created_at DESC LIMIT ?
      `).bind(limit).all();
  }
  const posts = (rows.results || []).reverse().map((row) => {
    const includeOwnPendingStatus = Boolean(viewer && row.author_id === viewer.id && row.status === "pending");
    return publicPost(row, url.origin, includeOwnPendingStatus);
  });
  const response = json({ posts }, 200, request, env, {
    "Cache-Control": viewer ? "no-store" : `public, max-age=${numberEnv(env, "FEED_CACHE_SECONDS", 20)}`
  });
  if (!viewer) {
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
  }
  return response;
}
__name(feed, "feed");
async function registerPushToken(request, env, ctx) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJSON(request);
  const token = cleanDeviceToken(body.token);
  const environment = allowedPushEnvironment(body.environment);
  const platform = cleanText(body.platform || "ios", 24) || "ios";
  const now = (/* @__PURE__ */ new Date()).toISOString();
  if (!token) {
    return json({ error: "Device token required." }, 400, request, env);
  }
  await env.DB.prepare(`
    INSERT INTO push_tokens (token, user_id, platform, environment, enabled, created_at, updated_at)
    VALUES (?, ?, ?, ?, 1, ?, ?)
    ON CONFLICT(token) DO UPDATE SET
      user_id = excluded.user_id,
      platform = excluded.platform,
      environment = excluded.environment,
      enabled = 1,
      updated_at = excluded.updated_at,
      failure_reason = ''
  `).bind(token, auth.user.id, platform, environment, now, now).run();
  if (auth.user.role === "admin") {
    await resumeWaitingAdminPushJobs(env);
    if (ctx && apnsConfigured(env)) {
      ctx.waitUntil(processPushNotificationJobs(env, numberEnv(env, "MAX_ADMIN_PUSH_RECIPIENTS_PER_EVENT", 20)));
    }
  }
  return json({ ok: true }, 200, request, env);
}
__name(registerPushToken, "registerPushToken");
async function unregisterPushToken(request, env, rawToken) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const token = cleanDeviceToken(rawToken);
  if (!token) return json({ error: "Device token required." }, 400, request, env);
  await env.DB.prepare("DELETE FROM push_tokens WHERE token = ? AND user_id = ?").bind(token, auth.user.id).run();
  return json({ ok: true }, 200, request, env);
}
__name(unregisterPushToken, "unregisterPushToken");
async function createPost(request, env, ctx) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.rules_accepted_at) {
    return json({ error: "Accept the community rules before posting." }, 403, request, env);
  }
  await consumeRateLimit(env, `post:${auth.user.id}`, numberEnv(env, "POSTS_PER_HOUR", 30), 3600);
  const body = await readJSON(request);
  const maxMessageChars = numberEnv(env, "MAX_MESSAGE_CHARS", 1400);
  const kind = allowedKind(String(body.kind || "update"));
  const message = cleanText(body.message, maxMessageChars);
  const dealURL = cleanURL(body.dealURL || body.dealUrl || "");
  const statsJSON = sanitizeStats(body.stats);
  const parsedImage = parseDataURL(body.imageBase64 || body.imageData || "");
  if (!message && !dealURL && !statsJSON && !parsedImage) {
    return json({ error: "Add a message, image, deal link, or stats." }, 400, request, env);
  }
  if (parsedImage && parsedImage.bytes.length > numberEnv(env, "MAX_IMAGE_BYTES", 1e6)) {
    return json({ error: "Image is too large. The app should compress images before upload." }, 413, request, env);
  }
  const blockedReason = moderationReason(`${message} ${dealURL}`, env);
  if (blockedReason) {
    return json({ error: "That message is blocked by the community filter." }, 400, request, env);
  }
  const autoApprove = String(env.AUTO_APPROVE_POSTS || "true").toLowerCase() !== "false";
  const requiresPhotoReview = Boolean(parsedImage && auth.user.role !== "admin");
  const status = requiresPhotoReview || !autoApprove ? "pending" : "approved";
  const moderationNote = status === "pending" ? (parsedImage ? "Photo pending admin approval" : "Awaiting moderation") : "";
  const id = crypto.randomUUID();
  const now = (/* @__PURE__ */ new Date()).toISOString();
  let imageKey = null;
  let imageMime = null;
  let imageBytes = 0;
  if (parsedImage) {
    imageBytes = parsedImage.bytes.length;
    const total = await currentMediaBytes(env);
    const maxTotal = numberEnv(env, "MAX_TOTAL_MEDIA_BYTES", 8e9);
    if (total + imageBytes > maxTotal) {
      return json({ error: "Community image storage is full. Ask the admin to clean up old images." }, 507, request, env);
    }
    imageMime = parsedImage.mime;
    imageKey = `${id}.${extensionForMime(imageMime)}`;
    await env.MEDIA.put(imageKey, parsedImage.bytes, {
      httpMetadata: {
        contentType: imageMime,
        cacheControl: "public, max-age=31536000, immutable"
      }
    });
    await setMediaBytes(env, total + imageBytes);
  }
  await env.DB.prepare(`
    INSERT INTO posts (id, author_id, kind, message, deal_url, stats_json, image_key, image_mime, image_bytes, status, moderation_reason, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id,
    auth.user.id,
    kind,
    message,
    dealURL,
    statsJSON,
    imageKey,
    imageMime,
    imageBytes,
    status,
    moderationNote,
    now,
    now
  ).run();
  const row = {
    id,
    author_id: auth.user.id,
    author_name: auth.user.username,
    author_email: auth.user.email,
    kind,
    message,
    deal_url: dealURL,
    stats_json: statsJSON,
    image_key: imageKey,
    image_mime: imageMime,
    image_bytes: imageBytes,
    status,
    moderation_reason: moderationNote,
    report_count: 0,
    created_at: now,
    updated_at: now
  };
  if (status === "approved") {
    ctx.waitUntil(invalidateFeedCache(new URL(request.url).origin));
    ctx.waitUntil(notifyUsersAboutPost(env, row, new URL(request.url).origin));
  } else {
    ctx.waitUntil(notifyAdminsAboutReview(env, row, new URL(request.url).origin));
  }
  return json({ post: publicPost(row, new URL(request.url).origin, true), status }, 201, request, env);
}
__name(createPost, "createPost");
async function image(request, env, postID) {
  const row = await env.DB.prepare("SELECT id, image_key, image_mime, status FROM posts WHERE id = ?").bind(postID).first();
  if (!row || !row.image_key) {
    return new Response("Not found", { status: 404 });
  }
  const object = await env.MEDIA.get(row.image_key);
  if (!object) return new Response("Not found", { status: 404 });
  return new Response(object.body, {
    headers: {
      "Content-Type": row.image_mime || object.httpMetadata?.contentType || "application/octet-stream",
      "Cache-Control": "public, max-age=31536000, immutable"
    }
  });
}
__name(image, "image");
async function deletePost(request, env, postID) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const row = await env.DB.prepare("SELECT author_id FROM posts WHERE id = ?").bind(postID).first();
  if (!row) return json({ error: "Post not found." }, 404, request, env);
  if (row.author_id !== auth.user.id && auth.user.role !== "admin") {
    return json({ error: "You can only delete your own posts." }, 403, request, env);
  }
  await deletePostByID(env, postID);
  return json({ ok: true }, 200, request, env);
}
__name(deletePost, "deletePost");
async function report(request, env, postID, ctx) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  await consumeRateLimit(env, `report:${auth.user.id}`, numberEnv(env, "REPORTS_PER_HOUR", 20), 3600);
  const body = await readJSON(request);
  const reason = cleanText(body.reason, 200);
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const id = crypto.randomUUID();
  await env.DB.prepare("INSERT OR IGNORE INTO reports (id, post_id, reporter_id, reason, created_at) VALUES (?, ?, ?, ?, ?)").bind(id, postID, auth.user.id, reason, now).run();
  const countRow = await env.DB.prepare("SELECT COUNT(*) AS count FROM reports WHERE post_id = ?").bind(postID).first();
  const reportCount = Number(countRow?.count || 0);
  if (reportCount >= 3) {
    await env.DB.prepare("UPDATE posts SET status = 'pending', report_count = ?, moderation_reason = 'Reported by users', updated_at = ? WHERE id = ?").bind(reportCount, now, postID).run();
    if (reportCount === 3) {
      const row = await postWithAuthor(env, postID);
      if (row) {
        ctx.waitUntil(notifyAdminsAboutReview(env, row, new URL(request.url).origin));
      }
    }
  } else {
    await env.DB.prepare("UPDATE posts SET report_count = ?, updated_at = ? WHERE id = ?").bind(reportCount, now, postID).run();
  }
  return json({ ok: true, reportCount }, 200, request, env);
}
__name(report, "report");
async function blockUser(request, env, blockedID, shouldBlock) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (blockedID === auth.user.id) {
    return json({ error: "You cannot block yourself." }, 400, request, env);
  }
  const target = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(blockedID).first();
  if (!target) return json({ error: "User not found." }, 404, request, env);
  if (shouldBlock) {
    await env.DB.prepare("INSERT OR IGNORE INTO user_blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)").bind(auth.user.id, blockedID, (/* @__PURE__ */ new Date()).toISOString()).run();
  } else {
    await env.DB.prepare("DELETE FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?").bind(auth.user.id, blockedID).run();
  }
  return json({ ok: true }, 200, request, env);
}
__name(blockUser, "blockUser");
async function adminPosts(request, env, url) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  const status = url.searchParams.get("status") || "pending";
  let rows;
  if (status === "all") {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        ORDER BY p.created_at DESC LIMIT 200
      `).all();
  } else if (status === "reported") {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        WHERE p.report_count > 0
        ORDER BY p.created_at DESC LIMIT 200
      `).all();
  } else {
    rows = await env.DB.prepare(`
        SELECT p.*, u.username AS author_name, u.email AS author_email
        FROM posts p JOIN users u ON p.author_id = u.id
        WHERE p.status = ?
        ORDER BY p.created_at DESC LIMIT 200
      `).bind(status).all();
  }
  return json({ posts: (rows.results || []).map((row) => publicPost(row, url.origin, true)) }, 200, request, env);
}
__name(adminPosts, "adminPosts");
async function adminReports(request, env, url) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  const rows = await env.DB.prepare(`
    SELECT
      r.id,
      r.post_id,
      r.reason,
      r.created_at,
      reporter.id AS reporter_id,
      reporter.username AS reporter_name,
      reporter.email AS reporter_email,
      p.author_id,
      author.username AS author_name,
      author.email AS author_email,
      p.kind,
      p.message,
      p.deal_url,
      p.image_key,
      p.stats_json,
      p.status,
      p.moderation_reason,
      p.report_count,
      p.created_at AS post_created_at
    FROM reports r
    JOIN posts p ON r.post_id = p.id
    JOIN users reporter ON r.reporter_id = reporter.id
    JOIN users author ON p.author_id = author.id
    WHERE p.report_count > 0
    ORDER BY r.created_at DESC
    LIMIT 300
  `).all();
  return json({ reports: (rows.results || []).map((row) => publicReport(row, url.origin)) }, 200, request, env);
}
__name(adminReports, "adminReports");
async function adminUpdatePost(request, env, postID, url, ctx) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  const body = await readJSON(request);
  const status = ["approved", "pending", "rejected"].includes(body.status) ? body.status : null;
  if (!status) return json({ error: "Invalid status." }, 400, request, env);
  const existing = await postWithAuthor(env, postID);
  if (!existing) return json({ ok: true, post: null, missing: true }, 200, request, env);
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const resolved = status === "approved" || status === "rejected";
  await env.DB.prepare(`
      UPDATE posts
      SET status = ?,
          moderation_reason = '',
          report_count = ?,
          updated_at = ?
      WHERE id = ?
    `).bind(status, resolved ? 0 : Number(existing.report_count || 0), now, postID).run();
  if (resolved) {
    await env.DB.prepare("DELETE FROM reports WHERE post_id = ?").bind(postID).run();
  }
  const updated = await postWithAuthor(env, postID);
  if (!updated) return json({ ok: true, post: null, missing: true }, 200, request, env);
  if (status === "approved" && updated && existing?.status !== "approved") {
    ctx.waitUntil(invalidateFeedCache(url.origin));
    ctx.waitUntil(notifyUsersAboutPost(env, updated, url.origin));
  }
  return json({ ok: true, post: updated ? publicPost(updated, url.origin, true) : null, status: updated.status }, 200, request, env);
}
__name(adminUpdatePost, "adminUpdatePost");
async function adminDeletePost(request, env, postID) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  const deleted = await deletePostByID(env, postID);
  if (!deleted) return json({ error: "Post not found." }, 404, request, env);
  return json({ ok: true }, 200, request, env);
}
__name(adminDeletePost, "adminDeletePost");
async function deletePostByID(env, postID) {
  const row = await env.DB.prepare("SELECT image_key, image_bytes FROM posts WHERE id = ?").bind(postID).first();
  if (!row) return false;
  if (row?.image_key) {
    await env.MEDIA.delete(row.image_key);
    await setMediaBytes(env, Math.max(0, await currentMediaBytes(env) - Number(row.image_bytes || 0)));
  }
  await env.DB.prepare("DELETE FROM reports WHERE post_id = ?").bind(postID).run();
  await env.DB.prepare("DELETE FROM posts WHERE id = ?").bind(postID).run();
  return true;
}
__name(deletePostByID, "deletePostByID");
async function adminUsers(request, env) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  const rows = await env.DB.prepare("SELECT id, username, email, role, status, created_at, rules_accepted_at FROM users ORDER BY created_at DESC LIMIT 300").all();
  return json({ users: (rows.results || []).map(publicUser) }, 200, request, env);
}
__name(adminUsers, "adminUsers");
async function adminUpdateUser(request, env, userID) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  const body = await readJSON(request);
  const status = ["active", "suspended"].includes(body.status) ? body.status : null;
  const role = ["user", "admin"].includes(body.role) ? body.role : null;
  if (!status && !role) return json({ error: "Nothing to update." }, 400, request, env);
  if (status === "suspended" && userID === auth.user.id) {
    return json({ error: "You cannot suspend your own admin account." }, 400, request, env);
  }
  if (status) {
    await env.DB.prepare("UPDATE users SET status = ?, updated_at = ? WHERE id = ?").bind(status, (/* @__PURE__ */ new Date()).toISOString(), userID).run();
  }
  if (role) {
    await env.DB.prepare("UPDATE users SET role = ?, updated_at = ? WHERE id = ?").bind(role, (/* @__PURE__ */ new Date()).toISOString(), userID).run();
  }
  const updated = await env.DB.prepare("SELECT id, username, email, role, status, created_at, rules_accepted_at, COALESCE(collection_visibility, 'friends') AS collection_visibility FROM users WHERE id = ?").bind(userID).first();
  return json({ ok: true, user: updated ? publicUser(updated) : null }, 200, request, env);
}
__name(adminUpdateUser, "adminUpdateUser");
async function updateCatalogModel(request, env) {
  const auth = await requireAdmin(request, env);
  if (auth.response) return auth.response;
  if (!String(env.GITHUB_TOKEN || "").trim()) {
    return json({ error: "GitHub token is not configured for catalog edits." }, 503, request, env);
  }
  const body = await readJSON(request);
  const isCreate = body.create === true || body.action === "create";
  const originalNumber = cleanText(body.originalNumber, 120) || cleanText(body?.originalModel?.number, 120);
  if (!isCreate && !originalNumber) {
    return json({ error: "Original model number is required." }, 400, request, env);
  }
  try {
    const result = await commitCatalogModelEditWithRetry(env, originalNumber, body.originalModel || {}, body.model || {}, {
      create: isCreate,
      isAdmin: true
    });
    return json({ ok: true, ...result }, 200, request, env);
  } catch (error) {
    const status = Number(error.status || 500);
    const message = error.message || "Catalog update failed.";
    return json({ error: message }, status >= 400 && status < 600 ? status : 500, request, env);
  }
}
__name(updateCatalogModel, "updateCatalogModel");
async function commitCatalogModelEditWithRetry(env, originalNumber, originalModel, editedModel, options = {}) {
  let lastError = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await commitCatalogModelEdit(env, originalNumber, originalModel, editedModel, options);
    } catch (error) {
      lastError = error;
      if (![409, 422].includes(Number(error.status || 0))) break;
      await sleep(250 * (attempt + 1));
    }
  }
  throw lastError || catalogHTTPError(500, "Catalog update failed.");
}
__name(commitCatalogModelEditWithRetry, "commitCatalogModelEditWithRetry");
async function commitCatalogModelEdit(env, originalNumber, originalModel, editedModel, options = {}) {
  const isCreate = Boolean(options.create);
  const owner = String(env.CATALOG_REPO_OWNER || "MattJones7416").trim();
  const repo = String(env.CATALOG_REPO_NAME || "Mattel-Disney-Pixar-Cars-Checklist").trim();
  const branch = String(env.CATALOG_REPO_BRANCH || "main").trim();
  const appCatalogPath = "PixarCarsChecklist/checked.json";
  const publicCatalogPath = "catalog-worker/public/catalog.json";
  const ref = await githubJSON(env, `repos/${owner}/${repo}/git/ref/heads/${encodeURIComponent(branch)}`);
  const baseCommitSha = ref?.object?.sha;
  if (!baseCommitSha) throw catalogHTTPError(502, "GitHub branch reference was missing a commit SHA.");
  const baseCommit = await githubJSON(env, `repos/${owner}/${repo}/git/commits/${baseCommitSha}`);
  const baseTreeSha = baseCommit?.tree?.sha;
  if (!baseTreeSha) throw catalogHTTPError(502, "GitHub base commit was missing a tree SHA.");
  const baseTreeEntries = await fetchGitHubTreeEntries(env, owner, repo, baseTreeSha);
  const appCatalogContent = await fetchGitHubTextFromTree(env, owner, repo, baseTreeEntries, appCatalogPath);
  const publicCatalogContent = await fetchGitHubTextFromTree(env, owner, repo, baseTreeEntries, publicCatalogPath);
  const appCatalogEntries = safeJSON(appCatalogContent, []);
  const publicCatalogEntries = safeJSON(publicCatalogContent, []);
  if (!Array.isArray(appCatalogEntries) || !Array.isArray(publicCatalogEntries)) {
    throw catalogHTTPError(502, "Cars catalogue files must both contain JSON arrays.");
  }
  const currentEntry = isCreate ? {} : appCatalogEntries.find((entry) => catalogEntryMatchesIdentity(entry, originalNumber));
  if (!isCreate && !currentEntry) {
    throw catalogHTTPError(404, `Could not find catalogue car ${originalNumber}.`);
  }
  const nextEntry = canonicalCatalogEntry(normalizeCatalogEntry(editedModel, currentEntry));
  const validationErrors = validateCatalogEntry(nextEntry);
  if (validationErrors.length > 0) {
    throw catalogHTTPError(400, validationErrors.join("\n"));
  }
  if (isCreate) {
    if (appCatalogEntries.some((entry) => catalogEntryMatchesIdentity(entry, nextEntry.number))) {
      throw catalogHTTPError(409, `Catalogue car ${nextEntry.number} already exists.`);
    }
  }
  const nextAppEntries = rebuildCatalogDistEntries(appCatalogEntries, isCreate ? null : currentEntry, nextEntry);
  const nextPublicEntries = rebuildCatalogDistEntries(publicCatalogEntries, isCreate ? null : currentEntry, nextEntry);
  const appBlob = await createGitHubBlob(env, owner, repo, `${JSON.stringify(nextAppEntries, null, 2)}\n`);
  const publicBlob = await createGitHubBlob(env, owner, repo, `${JSON.stringify(nextPublicEntries, null, 2)}\n`);
  const treeItems = [
    { path: appCatalogPath, mode: "100644", type: "blob", sha: appBlob.sha },
    { path: publicCatalogPath, mode: "100644", type: "blob", sha: publicBlob.sha }
  ];
  const tree = await githubJSON(env, `repos/${owner}/${repo}/git/trees`, {
    method: "POST",
    body: {
      base_tree: baseTreeSha,
      tree: treeItems
    }
  });
  const commit = await githubJSON(env, `repos/${owner}/${repo}/git/commits`, {
    method: "POST",
    body: {
      message: `${isCreate ? "Add" : "Update"} catalog model ${nextEntry.number}`,
      tree: tree.sha,
      parents: [baseCommitSha]
    }
  });
  await githubJSON(env, `repos/${owner}/${repo}/git/refs/heads/${encodeURIComponent(branch)}`, {
    method: "PATCH",
    body: {
      sha: commit.sha,
      force: false
    }
  });
  return {
    commit: commit.sha,
    sourcePath: appCatalogPath,
    distPath: publicCatalogPath,
    model: nextEntry
  };
}
__name(commitCatalogModelEdit, "commitCatalogModelEdit");
function catalogUserRestrictionError(isCreate, currentEntry, nextEntry) {
  return "Catalogue changes require an administrator account.";
}
__name(catalogUserRestrictionError, "catalogUserRestrictionError");
function catalogEntryIsPixarCars(entry) {
  return CATALOG_ALLOWED_TYPES.includes(String(entry?.type || "").trim());
}
__name(catalogEntryIsPixarCars, "catalogEntryIsPixarCars");
function normalizedCatalogFieldValue(value) {
  if (value == null) return "";
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : "";
  return String(value).trim();
}
__name(normalizedCatalogFieldValue, "normalizedCatalogFieldValue");
async function fetchCatalogSourceEntry(env, owner, repo, treeEntries, originalNumber, originalModel) {
  const candidates = [];
  const originalCandidate = normalizeCatalogEntry(originalModel, {});
  const originalPath = catalogSourcePath(originalCandidate);
  if (originalPath) candidates.push(originalPath);
  const originalType = cleanText(originalModel?.type, 80);
  for (const sourcePath of candidates) {
    const fetched = await fetchGitHubTextFromTree(env, owner, repo, treeEntries, sourcePath, true);
    if (!fetched) continue;
    const entry = safeParseJSON(fetched, null);
    if (catalogEntryMatchesIdentity(entry, originalNumber, originalType)) {
      return { path: sourcePath, entry };
    }
  }
  const originalSlug = slug(originalNumber);
  const jsonPaths = treeEntries.filter((item) => item.type === "blob" && item.path?.startsWith("src/") && item.path?.endsWith(".json")).map((item) => item.path);
  const likelyPaths = jsonPaths.filter((path) => path.includes(originalSlug));
  for (const sourcePath of [...likelyPaths, ...jsonPaths]) {
    const fetched = await fetchGitHubTextFromTree(env, owner, repo, treeEntries, sourcePath, true);
    if (!fetched) continue;
    const entry = safeParseJSON(fetched, null);
    if (catalogEntryMatchesIdentity(entry, originalNumber, originalType)) {
      return { path: sourcePath, entry };
    }
  }
  throw catalogHTTPError(404, `Could not find catalog source JSON for ${originalNumber}.`);
}
__name(fetchCatalogSourceEntry, "fetchCatalogSourceEntry");
function normalizeCatalogEntry(input, base) {
  const entry = { ...base };
  entry.checked = Boolean(base.checked ?? false);
  entry.built = Boolean(base.built ?? false);
  entry.name = cleanText(input.name ?? base.name, 240);
  entry.number = cleanText(input.number ?? base.number, 120);
  entry.productCode = cleanText(input.productCode ?? base.productCode ?? "", 120);
  entry.action = "update";
  entry.originalNumber = entry.number;
  entry.character = cleanText(input.character ?? base.character ?? "", 240);
  entry.firstReleaseYear = cleanOptionalInteger(input.firstReleaseYear ?? input.difficulty ?? base.firstReleaseYear ?? base.difficulty);
  entry.difficulty = entry.firstReleaseYear;
  entry.releaseCount = cleanOptionalInteger(input.releaseCount ?? input.sheets ?? base.releaseCount ?? base.sheets) ?? 0;
  entry.sheets = entry.releaseCount;
  entry.link = cleanText(input.link ?? base.link, 1200);
  entry.category = cleanText(input.category ?? base.category ?? "Uncategorized", 240);
  entry.type = cleanText(input.type ?? base.type, 80);
  entry.status = cleanText(input.status ?? base.status ?? "", 80);
  entry.series = cleanText(input.series ?? base.series ?? "", 240);
  entry.releaseDate = entry.firstReleaseYear == null ? cleanText(input.releaseDate ?? base.releaseDate ?? "", 40) : String(entry.firstReleaseYear);
  entry.instructionsLink = cleanText(input.instructionsLink ?? base.instructionsLink ?? "", 1200);
  entry["360View"] = cleanText(input["360View"] ?? input.threeSixtyView ?? base["360View"] ?? base.threeSixtyView ?? "", 1200);
  entry.description = cleanText(input.description ?? input.modelDescription ?? base.description ?? base.modelDescription ?? "", 6e3);
  entry.productimage = cleanText(input.productimage ?? input.productImage ?? base.productimage ?? base.productImage ?? "", 1200);
  entry.source = cleanText(base.source ?? "https://dpcarswiki.com/Special:VehicleDatabase", 1200);
  entry.sourceLicense = cleanText(base.sourceLicense ?? "CC BY-SA 4.0", 120);
  return entry;
}
__name(normalizeCatalogEntry, "normalizeCatalogEntry");
function canonicalCatalogEntry(entry) {
  const output = {};
  for (const key of CATALOG_SOURCE_KEYS) {
    if (key === "checked" || key === "built") {
      output[key] = Boolean(entry[key]);
    } else if (["difficulty", "firstReleaseYear", "sheets", "releaseCount"].includes(key)) {
      output[key] = entry[key] == null || entry[key] === "" ? null : Number(entry[key]);
    } else {
      output[key] = entry[key] == null ? "" : String(entry[key]);
    }
  }
  return output;
}
__name(canonicalCatalogEntry, "canonicalCatalogEntry");
function validateCatalogEntry(entry) {
  const errors = [];
  for (const key of ["number", "name", "category", "link", "type"]) {
    if (String(entry[key] || "").trim() === "") errors.push(`Missing or empty required field: "${key}".`);
  }
  if (typeof entry.checked !== "boolean") errors.push('"checked" must be a boolean.');
  if (!CATALOG_ALLOWED_TYPES.includes(entry.type)) {
    errors.push(`"type" must be one of: ${CATALOG_ALLOWED_TYPES.join(", ")}. Got: ${JSON.stringify(entry.type)}.`);
  }
  if (!CATALOG_ALLOWED_STATUS.includes(entry.status)) {
    errors.push(`"status" must be one of: ${CATALOG_ALLOWED_STATUS.map((s) => s === "" ? '""' : s).join(", ")}. Got: ${JSON.stringify(entry.status)}.`);
  }
  if (entry.firstReleaseYear != null) {
    const firstReleaseYear = Number(entry.firstReleaseYear);
    if (!Number.isInteger(firstReleaseYear) || firstReleaseYear < 2006 || firstReleaseYear > 2100) {
      errors.push(`"firstReleaseYear" must be 2006-2100 or null. Got: ${JSON.stringify(entry.firstReleaseYear)}.`);
    }
  }
  if (entry.releaseCount != null) {
    const releaseCount = Number(entry.releaseCount);
    if (!Number.isInteger(releaseCount) || releaseCount < 0) {
      errors.push(`"releaseCount" must be a non-negative integer. Got: ${JSON.stringify(entry.releaseCount)}.`);
    }
  }
  if (entry.releaseDate && !/^\d{4}(-\d{2}){0,2}$/.test(entry.releaseDate)) {
    errors.push(`"releaseDate" must be blank or yyyy, yyyy-MM, or yyyy-MM-dd. Got: ${JSON.stringify(entry.releaseDate)}.`);
  }
  return errors;
}
__name(validateCatalogEntry, "validateCatalogEntry");
function rebuildCatalogDistEntries(existingEntries, originalEntry, nextEntry) {
  const entries = existingEntries.filter((entry) => {
    const key = normalizedCatalogNumber(entry?.number);
    return (!originalKey || key !== normalizedCatalogNumber(originalEntry?.number)) && key !== normalizedCatalogNumber(nextEntry?.number);
  }).concat(nextEntry);
  entries.sort((a, b) => {
    const nameCompare = String(a.name || "").localeCompare(String(b.name || ""));
    if (nameCompare !== 0) return nameCompare;
    return String(a.number || "").localeCompare(String(b.number || ""));
  });
  return entries;
}
__name(rebuildCatalogDistEntries, "rebuildCatalogDistEntries");
function catalogSourcePath(entry) {
  const folder = slug(entry.type);
  const basename = `${slug(entry.category)}-${slug(entry.number)}-${slug(entry.name)}.json`;
  if (!folder || basename === "--.json") return "";
  return `src/${folder}/${basename}`;
}
__name(catalogSourcePath, "catalogSourcePath");
function slug(value) {
  return String(value || "").replace(/\p{P}/gu, " ").toLowerCase().trim().replace(/\s+/g, "-").replace(/[^\p{L}\p{N}-]/gu, "").replace(/-+/g, "-").replace(/^-|-$/g, "");
}
__name(slug, "slug");
function normalizedCatalogNumber(value) {
  return String(value || "").trim().toLowerCase();
}
__name(normalizedCatalogNumber, "normalizedCatalogNumber");
function normalizedCatalogType(value) {
  return String(value || "").trim().toLowerCase();
}
__name(normalizedCatalogType, "normalizedCatalogType");
function catalogEntryKey(entry) {
  return `${normalizedCatalogType(entry?.type)}\0${normalizedCatalogNumber(entry?.number)}`;
}
__name(catalogEntryKey, "catalogEntryKey");
function catalogEntryMatchesIdentity(entry, number, type = "") {
  if (normalizedCatalogNumber(entry?.number) !== normalizedCatalogNumber(number)) return false;
  const normalizedType = normalizedCatalogType(type);
  return !normalizedType || normalizedCatalogType(entry?.type) === normalizedType;
}
__name(catalogEntryMatchesIdentity, "catalogEntryMatchesIdentity");
function cleanOptionalInteger(value) {
  if (value === void 0 || value === null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : value;
}
__name(cleanOptionalInteger, "cleanOptionalInteger");
function cleanOptionalNumber(value) {
  if (value === void 0 || value === null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : value;
}
__name(cleanOptionalNumber, "cleanOptionalNumber");
async function fetchGitHubTreeEntries(env, owner, repo, treeSha) {
  const tree = await githubJSON(env, `repos/${owner}/${repo}/git/trees/${treeSha}?recursive=1`);
  return Array.isArray(tree?.tree) ? tree.tree : [];
}
__name(fetchGitHubTreeEntries, "fetchGitHubTreeEntries");
async function fetchGitHubTextFromTree(env, owner, repo, treeEntries, path, missingOK = false) {
  const entry = treeEntries.find((item) => item.type === "blob" && item.path === path);
  if (!entry?.sha) {
    if (missingOK) return null;
    throw catalogHTTPError(404, `GitHub tree entry was missing for ${path}.`);
  }
  const blob = await githubJSON(env, `repos/${owner}/${repo}/git/blobs/${entry.sha}`);
  if (typeof blob?.content !== "string" || blob.content.trim() === "") {
    throw catalogHTTPError(502, `GitHub blob response was empty for ${path}.`);
  }
  return blob.encoding === "base64" ? decodeBase64(blob.content) : blob.content;
}
__name(fetchGitHubTextFromTree, "fetchGitHubTextFromTree");
async function createGitHubBlob(env, owner, repo, content) {
  return githubJSON(env, `repos/${owner}/${repo}/git/blobs`, {
    method: "POST",
    body: {
      content,
      encoding: "utf-8"
    }
  });
}
__name(createGitHubBlob, "createGitHubBlob");
async function githubJSON(env, path, options = {}) {
  const token = String(env.GITHUB_TOKEN || "").trim();
  if (!token) throw catalogHTTPError(503, "GitHub token is not configured for catalog edits.");
  const url = `https://api.github.com/${path.replace(/^\/+/, "")}`;
  const response = await fetch(url, {
    method: options.method || "GET",
    headers: {
      "Accept": "application/vnd.github+json",
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      "User-Agent": "pixar-cars-checklist-admin",
      "X-GitHub-Api-Version": "2022-11-28"
    },
    body: options.body ? JSON.stringify(options.body) : void 0
  });
  const text = await response.text();
  const data = text ? safeParseJSON(text, null) : null;
  if (!response.ok) {
    const message = data?.message || `GitHub request failed (${response.status}).`;
    throw catalogHTTPError(response.status, message);
  }
  return data;
}
__name(githubJSON, "githubJSON");
function decodeBase64(value) {
  const binary = atob(String(value || "").replace(/\s/g, ""));
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return decoder.decode(bytes);
}
__name(decodeBase64, "decodeBase64");
function catalogHTTPError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}
__name(catalogHTTPError, "catalogHTTPError");
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
__name(sleep, "sleep");
async function postWithAuthor(env, postID) {
  return env.DB.prepare(`
    SELECT p.*, u.username AS author_name, u.email AS author_email
    FROM posts p JOIN users u ON p.author_id = u.id
    WHERE p.id = ?
  `).bind(postID).first();
}
__name(postWithAuthor, "postWithAuthor");
async function notifyUsersAboutPost(env, post, origin) {
  if (!apnsConfigured(env)) {
    console.log("APNs not configured; skipped user notification.");
    return;
  }
  const body = post.message ? `${post.author_name || "Collector"}: ${truncateForNotification(post.message)}` : `${post.author_name || "Collector"} shared a community post.`;
  await enqueuePushNotificationJob(env, {
    audience: "users",
    postID: post.id,
    authorID: post.author_id,
    title: "New Community Post",
    body,
    data: {
      type: "community_post",
      postID: post.id,
      url: `${origin}/v1/feed`
    }
  });
  await processPushNotificationJobs(env, numberEnv(env, "MAX_PUSH_RECIPIENTS_PER_EVENT", 40));
}
__name(notifyUsersAboutPost, "notifyUsersAboutPost");
async function notifyAdminsAboutReview(env, post, origin) {
  if (!apnsConfigured(env)) {
    console.log("APNs not configured; skipped admin notification.");
    return;
  }
  await enqueuePushNotificationJob(env, {
    audience: "admins",
    postID: post.id,
    authorID: post.author_id,
    title: "Post Awaiting Review",
    body: `${post.author_name || "Collector"} posted something for moderation.`,
    data: {
      type: "admin_review",
      postID: post.id,
      url: `${origin}/admin`
    }
  });
  await processPushNotificationJobs(env, numberEnv(env, "MAX_ADMIN_PUSH_RECIPIENTS_PER_EVENT", 20));
}
__name(notifyAdminsAboutReview, "notifyAdminsAboutReview");
async function enqueuePushNotificationJob(env, notification) {
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare(`
    INSERT INTO push_notification_jobs
      (id, audience, post_id, author_id, title, body, data_json, cursor_token, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, '', 'pending', ?, ?)
  `).bind(
    crypto.randomUUID(),
    notification.audience,
    notification.postID || "",
    notification.authorID || "",
    notification.title,
    notification.body,
    JSON.stringify(notification.data || {}),
    now,
    now
  ).run();
}
__name(enqueuePushNotificationJob, "enqueuePushNotificationJob");
async function processPushNotificationJobs(env, maxRecipients) {
  if (!apnsConfigured(env)) return;
  let remaining = Math.max(1, Math.min(maxRecipients || 40, 45));
  const jobs = await env.DB.prepare(`
    SELECT *
    FROM push_notification_jobs
    WHERE status = 'pending'
    ORDER BY created_at ASC
    LIMIT 5
  `).all();
  for (const job of jobs.results || []) {
    if (remaining <= 0) break;
    const recipients = await recipientsForPushJob(env, job, remaining);
    if (!recipients.length) {
      if (job.audience === "admins") {
        await waitForAdminPushRecipients(env, job.id);
      } else {
        await completePushNotificationJob(env, job.id);
      }
      continue;
    }
    let delivery;
    try {
      delivery = await sendPushNotifications(env, recipients, {
        title: job.title,
        body: job.body,
        data: safeJSON(job.data_json, {})
      });
    } catch (error) {
      console.error("APNs job processing failed", error);
      return;
    }
    if (delivery.sent === 0 && delivery.failed > 0) {
      await failPushNotificationJob(env, job.id, delivery.failureReasons.join(", ") || "APNs rejected all recipients.");
      continue;
    }
    const cursor = recipients[recipients.length - 1].token;
    const hasMore = await recipientsForPushJob(env, { ...job, cursor_token: cursor }, 1);
    if (hasMore.length) {
      await env.DB.prepare("UPDATE push_notification_jobs SET cursor_token = ?, updated_at = ? WHERE id = ?").bind(cursor, (/* @__PURE__ */ new Date()).toISOString(), job.id).run();
    } else {
      await completePushNotificationJob(env, job.id);
    }
    remaining -= recipients.length;
  }
}
__name(processPushNotificationJobs, "processPushNotificationJobs");
async function recipientsForPushJob(env, job, limit) {
  if (job.audience === "admins") {
    const rows2 = await env.DB.prepare(`
      SELECT t.token, t.environment, t.user_id
      FROM push_tokens t
      JOIN users u ON t.user_id = u.id
      WHERE t.enabled = 1
        AND u.status = 'active'
        AND u.role = 'admin'
        AND t.token > ?
      ORDER BY t.token ASC
      LIMIT ?
    `).bind(job.cursor_token || "", limit).all();
    return rows2.results || [];
  }
  const rows = await env.DB.prepare(`
    SELECT t.token, t.environment, t.user_id
    FROM push_tokens t
    JOIN users u ON t.user_id = u.id
    WHERE t.enabled = 1
      AND u.status = 'active'
      AND t.token > ?
      AND t.user_id != ?
      AND t.user_id NOT IN (SELECT blocker_id FROM user_blocks WHERE blocked_id = ?)
    ORDER BY t.token ASC
    LIMIT ?
  `).bind(job.cursor_token || "", job.author_id || "", job.author_id || "", limit).all();
  return rows.results || [];
}
__name(recipientsForPushJob, "recipientsForPushJob");
async function resumeWaitingAdminPushJobs(env) {
  await env.DB.prepare(`
    UPDATE push_notification_jobs
    SET status = 'pending', cursor_token = '', updated_at = ?
    WHERE audience = 'admins' AND status = 'waiting_for_recipients'
  `).bind((/* @__PURE__ */ new Date()).toISOString()).run();
}
__name(resumeWaitingAdminPushJobs, "resumeWaitingAdminPushJobs");
async function waitForAdminPushRecipients(env, jobID) {
  console.log("No admin push recipients registered; waiting to retry admin notification.");
  await env.DB.prepare("UPDATE push_notification_jobs SET status = 'waiting_for_recipients', updated_at = ? WHERE id = ?").bind((/* @__PURE__ */ new Date()).toISOString(), jobID).run();
}
__name(waitForAdminPushRecipients, "waitForAdminPushRecipients");
async function completePushNotificationJob(env, jobID) {
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare("UPDATE push_notification_jobs SET status = 'sent', completed_at = ?, updated_at = ? WHERE id = ?").bind(now, now, jobID).run();
}
__name(completePushNotificationJob, "completePushNotificationJob");
async function failPushNotificationJob(env, jobID, reason) {
  console.error(`APNs job failed: ${reason}`);
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare("UPDATE push_notification_jobs SET status = 'failed', completed_at = ?, updated_at = ? WHERE id = ?").bind(now, now, jobID).run();
}
__name(failPushNotificationJob, "failPushNotificationJob");
async function sendPushNotifications(env, recipients, notification) {
  const delivery = { sent: 0, failed: 0, failureReasons: [] };
  if (!recipients.length) return delivery;
  const jwt = await createAPNsJWT(env);
  const topic = String(env.APNS_BUNDLE_ID || "").trim();
  for (const recipient of recipients) {
    const result = await sendAPNsNotification(env, jwt, topic, recipient, notification);
    const now = (/* @__PURE__ */ new Date()).toISOString();
    if (result.ok) {
      delivery.sent += 1;
      await env.DB.prepare("UPDATE push_tokens SET last_success_at = ?, last_failure_at = NULL, failure_reason = '' WHERE token = ?").bind(now, recipient.token).run();
    } else {
      delivery.failed += 1;
      delivery.failureReasons.push(result.reason);
      await env.DB.prepare("UPDATE push_tokens SET last_failure_at = ?, failure_reason = ? WHERE token = ?").bind(now, result.reason, recipient.token).run();
      if (["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(result.reason)) {
        await env.DB.prepare("UPDATE push_tokens SET enabled = 0, updated_at = ? WHERE token = ?").bind(now, recipient.token).run();
      }
    }
  }
  return delivery;
}
__name(sendPushNotifications, "sendPushNotifications");
async function sendAPNsNotification(env, jwt, topic, recipient, notification) {
  const host = recipient.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const payload = {
    aps: {
      alert: {
        title: notification.title,
        body: notification.body
      },
      sound: "default"
    },
    ...notification.data
  };
  const response = await fetch(`${host}/3/device/${recipient.token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (response.ok) return { ok: true, reason: "" };
  const error = await response.json().catch(() => ({}));
  return { ok: false, reason: String(error.reason || `HTTP ${response.status}`) };
}
__name(sendAPNsNotification, "sendAPNsNotification");
async function createAPNsJWT(env) {
  const keyID = String(env.APNS_KEY_ID || "").trim();
  const teamID = String(env.APNS_TEAM_ID || "").trim();
  const header = { alg: "ES256", kid: keyID };
  const payload = { iss: teamID, iat: Math.floor(Date.now() / 1e3) };
  const signingInput = `${jsonToBase64URL(header)}.${jsonToBase64URL(payload)}`;
  const privateKey = await importAPNsPrivateKey(env);
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    encoder.encode(signingInput)
  ));
  return `${signingInput}.${bytesToBase64URL(ecdsaSignatureToJose(signature, 64))}`;
}
__name(createAPNsJWT, "createAPNsJWT");
async function importAPNsPrivateKey(env) {
  const pem = String(env.APNS_PRIVATE_KEY || "").replace(/\\n/g, "\n");
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "").replace(/-----END PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  if (!base64) throw new Error("APNS_PRIVATE_KEY is missing.");
  return crypto.subtle.importKey(
    "pkcs8",
    base64ToBytes(base64),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}
__name(importAPNsPrivateKey, "importAPNsPrivateKey");
function ecdsaSignatureToJose(signature, targetLength) {
  if (signature.length === targetLength) return signature;
  if (signature[0] !== 48) return signature;
  let offset = 2;
  if (signature[1] & 128) {
    offset = 2 + (signature[1] & 127);
  }
  if (signature[offset] !== 2) return signature;
  const rLength = signature[offset + 1];
  const r = signature.slice(offset + 2, offset + 2 + rLength);
  offset = offset + 2 + rLength;
  if (signature[offset] !== 2) return signature;
  const sLength = signature[offset + 1];
  const s = signature.slice(offset + 2, offset + 2 + sLength);
  const output = new Uint8Array(targetLength);
  output.set(trimIntegerBytes(r, targetLength / 2), 0);
  output.set(trimIntegerBytes(s, targetLength / 2), targetLength / 2);
  return output;
}
__name(ecdsaSignatureToJose, "ecdsaSignatureToJose");
function trimIntegerBytes(bytes, length) {
  let value = bytes;
  while (value.length > length && value[0] === 0) value = value.slice(1);
  if (value.length === length) return value;
  const output = new Uint8Array(length);
  output.set(value, length - value.length);
  return output;
}
__name(trimIntegerBytes, "trimIntegerBytes");
function apnsConfigured(env) {
  return Boolean(
    String(env.APNS_KEY_ID || "").trim() && String(env.APNS_TEAM_ID || "").trim() && String(env.APNS_BUNDLE_ID || "").trim() && String(env.APNS_PRIVATE_KEY || "").trim()
  );
}
__name(apnsConfigured, "apnsConfigured");
function cleanDeviceToken(value) {
  const token = String(value || "").replace(/[^a-f0-9]/gi, "").toLowerCase();
  return token.length >= 32 && token.length <= 256 ? token : "";
}
__name(cleanDeviceToken, "cleanDeviceToken");
function allowedPushEnvironment(value) {
  return String(value || "").toLowerCase() === "sandbox" ? "sandbox" : "production";
}
__name(allowedPushEnvironment, "allowedPushEnvironment");
function truncateForNotification(value) {
  const text = cleanText(value, 120).replace(/\s+/g, " ");
  return text.length > 100 ? `${text.slice(0, 97)}...` : text;
}
__name(truncateForNotification, "truncateForNotification");
async function requireUser(request, env) {
  const token = bearerToken(request);
  if (!token) return { response: json({ error: "Sign in required." }, 401, request, env) };
  const payload = await verifyToken(token, env);
  if (!payload) return { response: json({ error: "Sign in again." }, 401, request, env) };
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(payload.sub).first();
  if (!user || user.status !== "active") return { response: json({ error: "Account unavailable." }, 403, request, env) };
  return { user };
}
__name(requireUser, "requireUser");
async function optionalUser(request, env) {
  const token = bearerToken(request);
  if (!token) return null;
  const payload = await verifyToken(token, env);
  if (!payload) return null;
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(payload.sub).first();
  if (!user || user.status !== "active") return null;
  return user;
}
__name(optionalUser, "optionalUser");
async function requireAdmin(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  if (auth.user.role !== "admin") {
    return { response: json({ error: "Admin required." }, 403, request, env) };
  }
  return auth;
}
__name(requireAdmin, "requireAdmin");
async function consumeRateLimit(env, key, max, windowSeconds) {
  const now = Math.floor(Date.now() / 1e3);
  const resetAt = now + windowSeconds;
  const row = await env.DB.prepare("SELECT count, reset_at FROM rate_limits WHERE key = ?").bind(key).first();
  if (!row || Number(row.reset_at) <= now) {
    await env.DB.prepare("INSERT OR REPLACE INTO rate_limits (key, count, reset_at) VALUES (?, 1, ?)").bind(key, resetAt).run();
    return;
  }
  if (Number(row.count) >= max) {
    const retryAfter = Math.max(1, Number(row.reset_at) - now);
    const error = new Error("Rate limited");
    error.response = new Response(JSON.stringify({ error: "Slow down a moment.", retryAfter }), {
      status: 429,
      headers: { "Content-Type": "application/json", "Retry-After": String(retryAfter) }
    });
    throw error.response;
  }
  await env.DB.prepare("UPDATE rate_limits SET count = count + 1 WHERE key = ?").bind(key).run();
}
__name(consumeRateLimit, "consumeRateLimit");
async function readJSON(request) {
  if (!request.headers.get("content-type")?.includes("application/json")) return {};
  return request.json();
}
__name(readJSON, "readJSON");
function publicUser(row) {
  return {
    id: row.id,
    username: row.username,
    email: row.email,
    role: row.role,
    status: row.status,
    createdAt: row.created_at,
    rulesAcceptedAt: row.rules_accepted_at || null,
    collectionVisibility: allowedCollectionVisibility(row.collection_visibility) || "friends"
  };
}
__name(publicUser, "publicUser");
async function friendshipsForUser(env, userID) {
  const rows = await env.DB.prepare(`
    SELECT requester_id, addressee_id, status, created_at, updated_at
    FROM friendships
    WHERE requester_id = ? OR addressee_id = ?
  `).bind(userID, userID).all();
  return rows.results || [];
}
__name(friendshipsForUser, "friendshipsForUser");
async function friendshipBetween(env, userID, otherID) {
  return env.DB.prepare(`
    SELECT requester_id, addressee_id, status, created_at, updated_at
    FROM friendships
    WHERE (requester_id = ? AND addressee_id = ?)
       OR (requester_id = ? AND addressee_id = ?)
    LIMIT 1
  `).bind(userID, otherID, otherID, userID).first();
}
__name(friendshipBetween, "friendshipBetween");
function friendshipStatusForUser(targetID, viewerID, friendships) {
  if (targetID === viewerID) return "self";
  const row = (friendships || []).find((friendship) => {
    return friendship && (friendship.requester_id === targetID || friendship.addressee_id === targetID);
  });
  if (!row) return "none";
  if (row.status === "accepted") return "friends";
  if (row.requester_id === viewerID) return "requested";
  return "pending";
}
__name(friendshipStatusForUser, "friendshipStatusForUser");
function allowedCollectionVisibility(value) {
  const visibility = String(value || "").trim().toLowerCase();
  return ["friends", "everyone", "none"].includes(visibility) ? visibility : "";
}
__name(allowedCollectionVisibility, "allowedCollectionVisibility");
function canViewCollection(row, relationshipStatus, viewerID) {
  if (row.id === viewerID) return true;
  const visibility = allowedCollectionVisibility(row.collection_visibility) || "friends";
  if (visibility === "everyone") return true;
  if (visibility === "friends") return relationshipStatus === "friends";
  return false;
}
__name(canViewCollection, "canViewCollection");
function publicCommunityUser(row, viewerID, relationshipStatus) {
  const status = relationshipStatus || "none";
  return {
    id: row.id,
    username: row.username,
    role: row.role || "user",
    status: row.status || "active",
    createdAt: row.created_at || "",
    collectionVisibility: allowedCollectionVisibility(row.collection_visibility) || "friends",
    collectionUpdatedAt: row.collection_updated_at || "",
    collectionModelCount: clampInt(row.collection_model_count, 0, 1e6),
    friendshipStatus: status,
    canViewCollection: canViewCollection(row, status, viewerID)
  };
}
__name(publicCommunityUser, "publicCommunityUser");
function sanitizeCollectionModels(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 1e4).map(sanitizeCollectionModel).filter(Boolean);
}
__name(sanitizeCollectionModels, "sanitizeCollectionModels");
function sanitizeCollectionModel(value) {
  if (!value || typeof value !== "object") return null;
  const backupIdentifier = cleanText(value.backupIdentifier || value.number || value.modelNumber, 160);
  if (!backupIdentifier) return null;
  const quantity = clampInt(value.quantity, 0, 100);
  return {
    backupIdentifier,
    checked: value.checked === true || quantity > 0,
    built: value.built === true,
    isFavorite: value.isFavorite === true || value.favorite === true,
    isWishlisted: value.isWishlisted === true || value.wishlisted === true,
    quantity
  };
}
__name(sanitizeCollectionModel, "sanitizeCollectionModel");
function sanitizeStatsObject(value) {
  const stats = value && typeof value === "object" ? value : {};
  return {
    collected: clampInt(stats.collected, 0, 1e6),
    total: clampInt(stats.total, 0, 1e6),
    built: clampInt(stats.built, 0, 1e6),
    wishlisted: clampInt(stats.wishlisted, 0, 1e6),
    favorites: clampInt(stats.favorites, 0, 1e6)
  };
}
__name(sanitizeStatsObject, "sanitizeStatsObject");
function publicPost(row, origin, includeStatus = false) {
  const post = {
    id: row.id,
    authorID: row.author_id,
    authorName: row.author_name || "Collector",
    authorEmail: includeStatus ? row.author_email || "" : "",
    kind: row.kind,
    message: row.message || "",
    dealURL: row.deal_url || "",
    imageUrl: row.image_key && (row.status === "approved" || includeStatus) ? `${origin}/v1/posts/${row.id}/image` : null,
    stats: safeParseJSON(row.stats_json),
    reportCount: Number(row.report_count || 0),
    createdAt: row.created_at
  };
  if (includeStatus) {
    post.status = row.status;
    post.moderationReason = row.moderation_reason || "";
  }
  return post;
}
__name(publicPost, "publicPost");
function publicReport(row, origin) {
  return {
    id: row.id,
    postID: row.post_id,
    reason: row.reason || "",
    createdAt: row.created_at,
    reporterID: row.reporter_id,
    reporterName: row.reporter_name || "Collector",
    reporterEmail: row.reporter_email || "",
    authorID: row.author_id,
    authorName: row.author_name || "Collector",
    authorEmail: row.author_email || "",
    kind: row.kind,
    message: row.message || "",
    dealURL: row.deal_url || "",
    imageUrl: row.image_key ? `${origin}/v1/posts/${row.post_id}/image` : null,
    stats: safeParseJSON(row.stats_json),
    status: row.status,
    moderationReason: row.moderation_reason || "",
    reportCount: Number(row.report_count || 0),
    postCreatedAt: row.post_created_at
  };
}
__name(publicReport, "publicReport");
async function invalidateFeedCache(origin) {
  const cache = caches.default;
  const limits = [40, 60];
  await Promise.all(limits.map((limit) => cache.delete(new Request(`${origin}/v1/feed?limit=${limit}&before=`))));
}
__name(invalidateFeedCache, "invalidateFeedCache");
function cleanText(value, maxLength) {
  return String(value || "").replace(/\r\n/g, "\n").trim().slice(0, maxLength);
}
__name(cleanText, "cleanText");
function normalizeUsername(value) {
  return cleanText(value, 32).toLowerCase().replace(/\s+/g, " ");
}
__name(normalizeUsername, "normalizeUsername");
function cleanURL(value) {
  const text = cleanText(value, 500);
  if (!text) return "";
  try {
    const url = new URL(text);
    if (url.protocol !== "https:" && url.protocol !== "http:") return "";
    return url.toString();
  } catch {
    return "";
  }
}
__name(cleanURL, "cleanURL");
function allowedKind(value) {
  return ["update", "stats", "deal", "question"].includes(value) ? value : "update";
}
__name(allowedKind, "allowedKind");
function sanitizeStats(value) {
  if (!value || typeof value !== "object") return null;
  const stats = {
    collected: clampInt(value.collected, 0, 1e6),
    total: clampInt(value.total, 0, 1e6),
    built: clampInt(value.built, 0, 1e6),
    wishlisted: clampInt(value.wishlisted, 0, 1e6),
    favorites: clampInt(value.favorites, 0, 1e6)
  };
  return JSON.stringify(stats);
}
__name(sanitizeStats, "sanitizeStats");
function safeJSON(value, fallback) {
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}
__name(safeJSON, "safeJSON");
function clampInt(value, min, max) {
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n)) return min;
  return Math.min(max, Math.max(min, n));
}
__name(clampInt, "clampInt");
function parseDataURL(value) {
  const text = String(value || "");
  if (!text) return null;
  const match = text.match(/^data:(image\/(?:jpeg|png|webp));base64,([a-z0-9+/=]+)$/i);
  if (!match) return null;
  return { mime: match[1].toLowerCase(), bytes: base64ToBytes(match[2]) };
}
__name(parseDataURL, "parseDataURL");
function extensionForMime(mime) {
  if (mime === "image/png") return "png";
  if (mime === "image/webp") return "webp";
  return "jpg";
}
__name(extensionForMime, "extensionForMime");
function moderationReason(message, env) {
  const envWords = String(env.MODERATION_BLOCKED_WORDS || "").split(",").map((word) => word.trim().toLowerCase()).filter(Boolean);
  const words = [...DEFAULT_BLOCKED_TERMS, ...envWords];
  const normalized = normalizeForModeration(message);
  const hit = words.find((word) => {
    const needle = normalizeForModeration(word).trim();
    if (!needle) return false;
    return normalized.includes(` ${needle} `);
  });
  return hit ? "Matched moderation filter" : "";
}
__name(moderationReason, "moderationReason");
function normalizeForModeration(value) {
  return ` ${String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim()} `;
}
__name(normalizeForModeration, "normalizeForModeration");
async function currentMediaBytes(env) {
  const row = await env.DB.prepare("SELECT value FROM app_state WHERE key = 'media_bytes_total'").first();
  return Number(row?.value || 0);
}
__name(currentMediaBytes, "currentMediaBytes");
async function setMediaBytes(env, value) {
  await env.DB.prepare("INSERT OR REPLACE INTO app_state (key, value) VALUES ('media_bytes_total', ?)").bind(String(value)).run();
}
__name(setMediaBytes, "setMediaBytes");
async function hashPassword(password, saltBase64URL, env) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({
    name: "PBKDF2",
    salt: base64URLToBytes(saltBase64URL),
    iterations: numberEnv(env, "PASSWORD_PBKDF2_ITERATIONS", 1e5),
    hash: "SHA-256"
  }, key, 256);
  return bytesToBase64URL(new Uint8Array(bits));
}
__name(hashPassword, "hashPassword");
async function createToken(payload, env) {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1e3);
  const fullPayload = {
    ...payload,
    iss: env.JWT_ISSUER || "pixar-cars-social-api",
    iat: now,
    exp: now + 60 * 60 * 24 * 30
  };
  const signingInput = `${jsonToBase64URL(header)}.${jsonToBase64URL(fullPayload)}`;
  const signature = await hmac(signingInput, env.JWT_SECRET);
  return `${signingInput}.${signature}`;
}
__name(createToken, "createToken");
async function verifyToken(token, env) {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const expected = await hmac(`${parts[0]}.${parts[1]}`, env.JWT_SECRET);
  if (!timingSafeEqual(parts[2], expected)) return null;
  const payload = safeParseJSON(decoder.decode(base64URLToBytes(parts[1])));
  if (!payload || payload.exp < Math.floor(Date.now() / 1e3)) return null;
  return payload;
}
__name(verifyToken, "verifyToken");
async function hmac(value, secret) {
  if (!secret || String(secret).length < 24) {
    throw new Error("JWT_SECRET must be set to a long random string.");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return bytesToBase64URL(new Uint8Array(signature));
}
__name(hmac, "hmac");
function timingSafeEqual(a, b) {
  const left = String(a || "");
  const right = String(b || "");
  if (left.length !== right.length) return false;
  let result = 0;
  for (let index = 0; index < left.length; index += 1) {
    result |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return result === 0;
}
__name(timingSafeEqual, "timingSafeEqual");
function bearerToken(request) {
  const header = request.headers.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : "";
}
__name(bearerToken, "bearerToken");
function clientIP(request) {
  return request.headers.get("CF-Connecting-IP") || request.headers.get("x-forwarded-for") || "unknown";
}
__name(clientIP, "clientIP");
async function hashedClientIP(request, env) {
  return hmac(`rate-limit:${clientIP(request)}`, env.JWT_SECRET);
}
__name(hashedClientIP, "hashedClientIP");
function numberEnv(env, key, fallback) {
  const parsed = Number.parseInt(env[key], 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}
__name(numberEnv, "numberEnv");
function jsonToBase64URL(value) {
  return bytesToBase64URL(encoder.encode(JSON.stringify(value)));
}
__name(jsonToBase64URL, "jsonToBase64URL");
function bytesToBase64URL(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
__name(bytesToBase64URL, "bytesToBase64URL");
function base64URLToBytes(value) {
  const base64 = String(value).replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(String(value).length / 4) * 4, "=");
  return base64ToBytes(base64);
}
__name(base64URLToBytes, "base64URLToBytes");
function base64ToBytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}
__name(base64ToBytes, "base64ToBytes");
function randomBase64URL(length) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytesToBase64URL(bytes);
}
__name(randomBase64URL, "randomBase64URL");
function safeParseJSON(value) {
  if (!value) return null;
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}
__name(safeParseJSON, "safeParseJSON");
function html(body, request, env) {
  return withCors(new Response(body, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store"
    }
  }), request, env);
}
__name(html, "html");
function json(body, status, request, env, extraHeaders = {}) {
  return withCors(new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders
    }
  }), request, env);
}
__name(json, "json");
function withCors(response, request, env) {
  const headers = new Headers(response.headers);
  const origin = request.headers.get("Origin") || "*";
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Vary", "Origin");
  headers.set("Access-Control-Allow-Methods", "GET,POST,PATCH,DELETE,OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization,Content-Type");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}
__name(withCors, "withCors");
export {
  worker_default as default
};
//# sourceMappingURL=worker.js.map
