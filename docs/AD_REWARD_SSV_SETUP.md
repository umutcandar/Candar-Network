# Secure AdMob SSV rollout

This branch removes client-authorized rewarded boost grants. Release in
the correct order to avoid interrupting current players:

1. Deploy the new `admob_ssv` function at
   `https://europe-west1-candar-network-007.cloudfunctions.net/admob_ssv`.
   Its unsigned test requests must return HTTP 403.
2. In the Google AdMob dashboard, enable server-side verification on
   the iOS rewarded unit ending `4038775406` and Android rewarded unit
   ending `9932720942`. Configure each to use the callback URL above.
   Run the AdMob dashboard's signed callback test.
3. Release the updated mobile builds that attach the Firebase UID and
   reserved attempt timestamp as SSV user_id and custom_data.
4. Only then deploy the new `apply_rewarded_boost` implementation that
   **checks** server grants rather than granting from client calls.
   Old builds do not attach SSV metadata and need an upgrade.
5. Verify real iOS/Android rewarded grants and cancellation cases.

The callback verifies Google's signature with rotating public keys, checks
timestamp, trusted rewarded unit, transaction uniqueness and reserved attempt.
Never claim production rollout is done before the AdMob callback setting,
Firebase deployment and mobile release have been validated.

Official docs: https://developers.google.com/admob/android/ssv
