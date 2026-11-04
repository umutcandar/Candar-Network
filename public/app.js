import { initializeApp } from "https://www.gstatic.com/firebasejs/10.13.1/firebase-app.js";
import { getAuth, GoogleAuthProvider, signInWithPopup, onAuthStateChanged, signOut } from "https://www.gstatic.com/firebasejs/10.13.1/firebase-auth.js";
import { getFunctions, httpsCallable } from "https://www.gstatic.com/firebasejs/10.13.1/firebase-functions.js";
import { firebaseConfig, ADMIN_EMAILS } from "./firebase-config.js";

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const provider = new GoogleAuthProvider();
const functions = getFunctions(app, "europe-west1");
const getOverview = httpsCallable(functions, "admin_get_overview");
const updateConfig = httpsCallable(functions, "admin_update_config");
const $ = (id) => document.getElementById(id);
let busy = false;

function isAdmin(email) {
  // This is only a UI convenience. Server-side requireOwner is authoritative.
  return ADMIN_EMAILS.includes(String(email || "").toLowerCase());
}
async function loadOverview() {
  const result = (await getOverview({})).data;
  if ($("userCount")) $("userCount").textContent = "Toplam kullanıcı: " + result.userCount;
  if ($("miningRate")) $("miningRate").value = result.miningRate;
}
async function saveConfig() {
  if (busy) return;
  busy = true;
  const button = $("saveConfig");
  const status = $("saveMsg");
  if (button) button.disabled = true;
  if (status) status.textContent = "Kaydediliyor...";
  try {
    const rate = Number($("miningRate")?.value);
    const result = (await updateConfig({ miningRate: rate })).data;
    if (status) status.textContent = "Kaydedildi (" + result.miningRate + "). Yeni hesaplarda geçerli.";
  } catch (err) {
    if (status) status.textContent = "Kaydetme başarısız: " + (err?.message || "Yetki veya bağlantı hatası.");
  } finally {
    busy = false;
    if (button) button.disabled = false;
  }
}
onAuthStateChanged(auth, async (user) => {
  if ($("googleBtn")) $("googleBtn").style.display = user ? "none" : "inline-block";
  if ($("signOutBtn")) $("signOutBtn").style.display = user ? "inline-block" : "none";
  if ($("adminStatus")) $("adminStatus").textContent = user ? "Yetki kontrol ediliyor..." : "Giriş yapmadınız.";
  if ($("panel")) $("panel").style.display = "none";
  if ($("me")) $("me").style.display = user ? "block" : "none";
  if ($("meJson") && user) $("meJson").textContent = JSON.stringify({
    uid: user.uid, email: user.email, name: user.displayName
  }, null, 2);

  if (!user) return;
  if (!isAdmin(user.email)) {
    if ($("adminStatus")) $("adminStatus").textContent = "Bu hesap yönetici listesinde değil.";
    return;
  }
  try {
    await loadOverview();
    if ($("adminStatus")) $("adminStatus").textContent = "Yönetici girişi doğrulandı.";
    if ($("panel")) $("panel").style.display = "block";
  } catch (err) {
    if ($("adminStatus")) $("adminStatus").textContent = "Sunucu yetkisi doğrulanamadı: " + (err?.message || "Hata");
  }
});
if ($("googleBtn")) $("googleBtn").addEventListener("click", () => signInWithPopup(auth, provider).catch(console.error));
if ($("signOutBtn")) $("signOutBtn").addEventListener("click", () => signOut(auth));
if ($("adminLogin")) $("adminLogin").addEventListener("click", () => signInWithPopup(auth, provider).catch(console.error));
if ($("adminLogout")) $("adminLogout").addEventListener("click", () => signOut(auth));
if ($("saveConfig")) $("saveConfig").addEventListener("click", saveConfig);
