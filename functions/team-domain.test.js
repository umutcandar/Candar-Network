"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  TEAM_CAPACITY, normalizeTeamName, normalizeTeamCode,
  normalizeMembers, addMember, removeMember,
} = require("./team-domain");

test("team names support world languages but reject unsafe input", () => {
  assert.equal(normalizeTeamName("  Candar    Birliği "), "Candar Birliği");
  assert.equal(normalizeTeamName("فريق الأبطال"), "فريق الأبطال");
  assert.equal(normalizeTeamName("x"), "");
  assert.equal(normalizeTeamName("<script>alert(1)</script>"), "");
  assert.equal(normalizeTeamName("hello\nworld"), "hello world");
});
test("team codes are strong, uppercase and strict", () => {
  assert.equal(normalizeTeamCode(" t0a1b2c3d4e5f "), "T0A1B2C3D4E5F");
  assert.equal(normalizeTeamCode("123456"), "");
  assert.equal(normalizeTeamCode("T0A1B2C3D4E5F/"), "");
});
test("joining and leaving never duplicates a member", () => {
  const team = { members: ["owner"], ownerUid: "owner" };
  assert.deepEqual(addMember(team, "owner"), { members: ["owner"], alreadyMember: true });
  assert.deepEqual(addMember(team, "guest"), { members: ["owner", "guest"] });
  assert.deepEqual(removeMember(team, "missing"), { members: ["owner"], wasMember: false });
});
test("owner exit transfers to next member; last exit disbands", () => {
  assert.deepEqual(removeMember({ members: ["owner", "guest"], ownerUid: "owner" }, "owner"), {
    members: ["guest"], wasMember: true, disbanded: false, ownerUid: "guest",
  });
  assert.deepEqual(removeMember({ members: ["owner"], ownerUid: "owner" }, "owner"), {
    members: [], wasMember: true, disbanded: true, ownerUid: "",
  });
});
test("team capacity and duplicate input", () => {
  assert.equal(TEAM_CAPACITY, 30);
  assert.equal(addMember({ members: Array.from({ length: TEAM_CAPACITY }, (_, i) => "u" + i) }, "next").full, true);
  assert.deepEqual(normalizeMembers(["a", "a", "", null, "b"]), ["a", "b"]);
});
