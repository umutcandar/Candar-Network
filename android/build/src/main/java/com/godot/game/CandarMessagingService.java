package com.godot.game;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class CandarMessagingService extends FirebaseMessagingService {
    private static final String CHANNEL_ID = "daily_points";

    @Override
    public void onNewToken(@NonNull String token) {
        super.onNewToken(token);
        persistToken(this, token);
    }

    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        super.onMessageReceived(message);
        RemoteMessage.Notification notification = message.getNotification();
        if (notification == null) {
            return;
        }

        ensureChannel();
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launchIntent == null) {
            return;
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_candar)
                .setContentTitle(notification.getTitle())
                .setContentText(notification.getBody())
                .setStyle(new NotificationCompat.BigTextStyle().bigText(notification.getBody()))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent);

        try {
            NotificationManagerCompat.from(this).notify(
                    (int) (System.currentTimeMillis() & 0x7fffffff),
                    builder.build()
            );
        } catch (SecurityException error) {
            Log.w("CandarPush", "Bildirim izni verilmedi", error);
        }
    }

    static void persistToken(Context context, String token) {
        if (token == null || token.trim().isEmpty()) {
            return;
        }
        try {
            JSONObject payload = new JSONObject();
            payload.put("token", token);
            payload.put("platform", "android");
            payload.put("updated_at", System.currentTimeMillis() / 1000L);
            byte[] bytes = payload.toString().getBytes(StandardCharsets.UTF_8);
            writeFile(new File(context.getFilesDir(), "fcm_token.json"), bytes);

            File godotDir = new File(context.getFilesDir(), "app_userdata/Candar Network");
            if (godotDir.exists() || godotDir.mkdirs()) {
                writeFile(new File(godotDir, "fcm_token.json"), bytes);
            }
        } catch (JSONException | IOException error) {
            Log.e("CandarPush", "FCM token dosyası yazılamadı", error);
        }
    }

    private static void writeFile(File target, byte[] bytes) throws IOException {
        try (FileOutputStream stream = new FileOutputStream(target, false)) {
            stream.write(bytes);
        }
    }

    private void ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.candar_daily_channel_name),
                    NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription(getString(R.string.candar_daily_channel_description));
            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(channel);
        }
    }
}
