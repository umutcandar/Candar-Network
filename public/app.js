import { initializeApp } from "https://www.gstatic.com/firebasejs/10.13.1/firebase-app.js";
import { getAuth, GoogleAuthProvider, signInWithPopup, onAuthStateChanged, signOut } from "https://www.gstatic.com/firebasejs/10.13.1/firebase-auth.js";
import { getFirestore, doc, getDoc, setDoc, updateDoc, serverTimestamp, collection, getCountFromServer } from "https://www.gstatic.com/firebasejs/10.13.1/firebase-firestore.js";
import { firebaseConfig, ADMIN_EMAILS } from "./firebase-config.js";
const app = initializeApp(firebaseConfig); const auth = getAuth(app); const db = getFirestore(app); const provider = new GoogleAuthProvider();
const $=id=>document.getElementById(id);
async function ensureUserDoc(u){const r=doc(db,"users",u.uid);const s=await getDoc(r);const d={email:u.email||null,name:u.displayName||null,photoURL:u.photoURL||null,lastLoginAt:serverTimestamp()}; if(!s.exists()) await setDoc(r,{createdAt:serverTimestamp(),miningRate:0.80,...d}); else await updateDoc(r,d);}
async function readConfig(){const s=await getDoc(doc(db,"config","general")); if(s.exists()) { const v=s.data().mining_rate; const i=$("miningRate"); if(i&&v!=null) i.value=v; } }
async function saveConfig(){const i=$("miningRate"); $("saveMsg").textContent="Kaydediliyor..."; await setDoc(doc(db,"config","general"),{mining_rate:Number(i.value||0.80),updatedAt:serverTimestamp()},{merge:true}); $("saveMsg").textContent="✓ Kaydedildi"; setTimeout(()=>$("saveMsg").textContent="",1500);}
async function countUsers(){const c=collection(db,"users"); const n=await getCountFromServer(c); const el=$("userCount"); if(el) el.textContent="Toplam kullanıcı: "+n.data().count;}
function isAdmin(e){return ADMIN_EMAILS.includes((e||'').toLowerCase());}
onAuthStateChanged(auth, async (u)=>{const g=$("googleBtn"),o=$("signOutBtn"),m=$("me"),mj=$("meJson"),al=$("adminLogin"),ao=$("adminLogout"),as=$("adminStatus"),p=$("panel");
  if(g) g.style.display=u?"none":"inline-block"; if(o) o.style.display=u?"inline-block":"none";
  if(u){ await ensureUserDoc(u); if(m&&mj){ m.style.display="block"; mj.textContent=JSON.stringify({uid:u.uid,email:u.email,name:u.displayName,photo:u.photoURL},null,2); }
    if(as){ if(isAdmin(u.email)){ as.textContent="Yönetici girişi onaylandı."; if(p) p.style.display="block"; await readConfig(); await countUsers(); } else { as.textContent="Bu e-posta yönetici listesinde değil."; if(p) p.style.display="none"; } } }
  else { if(m) m.style.display="none"; if(as){ as.textContent="Giriş yapmadınız."; if(p) p.style.display="none"; } }});
if($("googleBtn")) $("googleBtn").addEventListener("click",()=>signInWithPopup(auth,provider));
if($("signOutBtn")) $("signOutBtn").addEventListener("click",()=>signOut(auth));
if($("adminLogin")) $("adminLogin").addEventListener("click",()=>signInWithPopup(auth,provider));
if($("adminLogout")) $("adminLogout").addEventListener("click",()=>signOut(auth));
if($("saveConfig")) $("saveConfig").addEventListener("click",saveConfig);
