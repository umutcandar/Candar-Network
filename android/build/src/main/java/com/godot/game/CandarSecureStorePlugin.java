package com.godot.game;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.NonNull;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.security.GeneralSecurityException;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Native Firebase refresh-token storage.
 *
 * Only an AES-256-GCM ciphertext is kept in app-private preferences.
 * The AES key is non-exportable and lives in AndroidKeyStore; backup
 * restoration of an unreadable ciphertext invalidates the session.
 * Never log any token, ciphertext or keystore exception details.
 */
public final class CandarSecureStorePlugin extends GodotPlugin {
    private static final String PLUGIN_NAME = "CandarSecureStore";
    private static final String KEY_ALIAS = "candar_firebase_refresh_key_v1";
    private static final String PREF_FILE = "candar_secure_session_v1";
    private static final String PREF_TOKEN = "refresh_ciphertext";
    private static final String STORE = "AndroidKeyStore";
    private static final int IV_LENGTH = 12;
    private static final int TAG_BITS = 128;

    public CandarSecureStorePlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return PLUGIN_NAME;
    }

    private SharedPreferences preferences() {
        Activity activity = getActivity();
        if (activity == null) return null;
        return activity.getApplicationContext().getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE);
    }

    private SecretKey getKey(boolean create) throws GeneralSecurityException {
        KeyStore store = KeyStore.getInstance(STORE);
        try {
            store.load(null);
        } catch (java.io.IOException error) {
            throw new GeneralSecurityException("Keystore could not be loaded", error);
        }
        java.security.Key existing = store.getKey(KEY_ALIAS, null);
        if (existing instanceof SecretKey) return (SecretKey) existing;
        if (!create) return null;

        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, STORE);
        KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(
                KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build();
        generator.init(spec);
        return generator.generateKey();
    }

    @UsedByGodot
    public boolean saveRefreshToken(String token) {
        SharedPreferences prefs = preferences();
        if (prefs == null || token == null || token.length() < 16 || token.length() > 8192) return false;
        try {
            SecretKey key = getKey(true);
            byte[] iv = new byte[IV_LENGTH];
            new SecureRandom().nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            byte[] ciphertext = cipher.doFinal(token.getBytes(StandardCharsets.UTF_8));
            byte[] joined = Arrays.copyOf(iv, iv.length + ciphertext.length);
            System.arraycopy(ciphertext, 0, joined, iv.length, ciphertext.length);
            return prefs.edit().putString(PREF_TOKEN, Base64.encodeToString(joined, Base64.NO_WRAP)).commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    @UsedByGodot
    public String loadRefreshToken() {
        SharedPreferences prefs = preferences();
        if (prefs == null) return "";
        String stored = prefs.getString(PREF_TOKEN, "");
        if (stored == null || stored.isEmpty()) return "";
        try {
            byte[] joined = Base64.decode(stored, Base64.NO_WRAP);
            if (joined.length <= IV_LENGTH + (TAG_BITS / 8)) throw new GeneralSecurityException("Invalid ciphertext");
            SecretKey key = getKey(false);
            if (key == null) throw new GeneralSecurityException("Key no longer exists");
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key,
                    new GCMParameterSpec(TAG_BITS, Arrays.copyOf(joined, IV_LENGTH)));
            byte[] raw = cipher.doFinal(Arrays.copyOfRange(joined, IV_LENGTH, joined.length));
            return new String(raw, StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            // Key invalidated, tampered data or backup-restore mismatch.
            prefs.edit().remove(PREF_TOKEN).commit();
            return "";
        }
    }

    @UsedByGodot
    public boolean clearRefreshToken() {
        SharedPreferences prefs = preferences();
        return prefs != null && prefs.edit().remove(PREF_TOKEN).commit();
    }
}
