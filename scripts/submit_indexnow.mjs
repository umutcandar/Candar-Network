const host = "candarnetwork.com";
const key = "396e33cc890eec460f63df9a414c8d87";
const keyLocation = `https://${host}/${key}.txt`;
const urlList = [
  `https://${host}/`,
  `https://${host}/download`,
  `https://${host}/en/`,
  `https://${host}/en/download`,
  `https://${host}/guides/7-day-streak-challenge`,
  `https://${host}/guides/daily-streak-app`
];

const response = await fetch("https://api.indexnow.org/indexnow", {
  method: "POST",
  headers: {"content-type": "application/json; charset=utf-8"},
  body: JSON.stringify({host, key, keyLocation, urlList})
});

if (![200, 202].includes(response.status)) {
  const body = await response.text();
  throw new Error(`IndexNow submission failed (${response.status}): ${body}`);
}

console.log(`IndexNow accepted ${urlList.length} URLs with HTTP ${response.status}.`);
