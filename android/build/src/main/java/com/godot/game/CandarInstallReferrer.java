package com.godot.game;

import android.content.Context;
import android.net.Uri;
import android.util.Log;

import com.android.installreferrer.api.InstallReferrerClient;
import com.android.installreferrer.api.InstallReferrerStateListener;
import com.android.installreferrer.api.ReferrerDetails;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

final class CandarInstallReferrer {
    private static final String PREFS = "candar_install_referrer";
    private static final String PROCESSED = "processed_v1";
    private static final Pattern REFERRAL_CODE = Pattern.compile("^[A-Za-z0-9_-]{4,32}$");

    private CandarInstallReferrer() {}

    static void captureOnce(Context context) {
        Context appContext = context.getApplicationContext();
        if (appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(PROCESSED, false)) {
            return;
        }

        InstallReferrerClient client = InstallReferrerClient.newBuilder(appContext).build();
        client.startConnection(new InstallReferrerStateListener() {
            @Override
            public void onInstallReferrerSetupFinished(int responseCode) {
                try {
                    if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                        return;
                    }
                    ReferrerDetails details = client.getInstallReferrer();
                    String raw = details == null ? "" : details.getInstallReferrer();
                    String code = Uri.parse("https://candarnetwork.com/?" + raw)
                            .getQueryParameter("ref");
                    if (code != null && REFERRAL_CODE.matcher(code).matches()) {
                        persistReferral(appContext, code);
                    }
                    appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .edit().putBoolean(PROCESSED, true).apply();
                } catch (Exception error) {
                    Log.w("CandarReferral", "Install referrer okunamadı", error);
                } finally {
                    client.endConnection();
                }
            }

            @Override
            public void onInstallReferrerServiceDisconnected() {
                // Sonraki açılışta tekrar denenecek; processed bayrağı yazılmaz.
            }
        });
    }

    private static void persistReferral(Context context, String code) throws Exception {
        JSONObject payload = new JSONObject();
        payload.put("code", code);
        payload.put("source", "install_referrer");
        payload.put("captured_at", System.currentTimeMillis() / 1000L);
        byte[] bytes = payload.toString().getBytes(StandardCharsets.UTF_8);

        writeFile(new File(context.getFilesDir(), "pending_referral.txt"), bytes);
        File godotDir = new File(context.getFilesDir(), "app_userdata/Candar Network");
        if (godotDir.exists() || godotDir.mkdirs()) {
            writeFile(new File(godotDir, "pending_referral.txt"), bytes);
        }
    }

    private static void writeFile(File target, byte[] bytes) throws Exception {
        try (FileOutputStream stream = new FileOutputStream(target, false)) {
            stream.write(bytes);
        }
    }
}
