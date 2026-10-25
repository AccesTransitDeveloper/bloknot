# Настройка уведомлений Android

Для напоминаний после закрытия приложения и перезагрузки телефона добавьте в
`android/app/src/main/AndroidManifest.xml` разрешения внутри `<manifest>`:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

Внутри `<application>` добавьте получатели уведомлений:

```xml
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver
    android:enabled="false"
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```

Проверьте Gradle-настройки по документации `flutter_local_notifications`:

- `compileSdk` не ниже 36;
- Java/Kotlin target 17;
- включён core library desugaring;
- `com.android.tools:desugar_jdk_libs:2.1.4` добавлен в зависимости;
- Android Gradle Plugin не ниже 8.11.1.

Код запрашивает разрешения уведомлений и точных будильников у пользователя.
Если разрешение на точное время не дано, Android может показать напоминание с
небольшой задержкой. При отключённых уведомлениях приложение всё равно
сохранит заметку, но напомнить не сможет.
