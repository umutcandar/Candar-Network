"use strict";

const TEAM_CAPACITY = 30;

function normalizeTeamName(raw) {
  const name = String(raw || "").normalize("NFC").trim().replace(/\s+/g, " ");
  // Unicode lettering is supported, but controls and Firestore path fragments
  // are not permitted in user-visible team names.
  if (name.length < 3 || name.length > 40 ||
      /[<>\u0000-\u001F\u007F]/u.test(name)) {
    return "";
  }
  return name;
}

function normalizeTeamCode(raw) {
  const code = String(raw || "").trim().toUpperCase();
  return /^T[A-F0-9]{12}$/.test(code) ? code : "";
}

function normalizeMembers(raw) {
  if (!Array.isArray(raw)) return [];
  const members = raw.filter((uid) =>
    typeof uid === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(uid)
  );
  return [...new Set(members)];
}

// Pure domain transitions; Firestore commits them atomically.
function addMember(team, uid) {
  const members = normalizeMembers(team?.members);
  if (members.includes(uid)) return { members, alreadyMember: true };
  if (members.length >= TEAM_CAPACITY) return { members, full: true };
  return { members: [...members, uid] };
}

function removeMember(team, uid) {
  const members = normalizeMembers(team?.members);
  if (!members.includes(uid)) return { members, wasMember: false };
  const remaining = members.filter((member) => member !== uid);
  const previousOwner = String(team?.ownerUid || "");
  return {
    members: remaining,
    wasMember: true,
    disbanded: remaining.length === 0,
    ownerUid: previousOwner === uid ? remaining[0] || "" : previousOwner,
  };
}

module.exports = {
  TEAM_CAPACITY,
  normalizeTeamName,
  normalizeTeamCode,
  normalizeMembers,
  addMember,
  removeMember,
};
