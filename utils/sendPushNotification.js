export async function sendPushNotification(expoPushToken, message) {
  const payload = {
    to: expoPushToken,
    sound: 'default',
    title: 'Kazım Zamanı!',
    body: message,
    data: { screen: 'Home' }
  };

  await fetch('https://exp.host/--/api/v2/push/send', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Accept-encoding': 'gzip, deflate',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });
}
