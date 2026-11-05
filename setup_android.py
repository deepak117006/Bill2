"""Creates the Android project files and patches them (internet access, plain-HTTP to the PC on your Wi-Fi, app name, icon)."""
import os, re, subprocess, shutil
sh = os.name == "nt"
run = lambda *a: subprocess.run(a, check=True, shell=sh)
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not os.path.isdir("android"):
    run("flutter", "create", "--platforms=android", "--org", "com.perixa", "--project-name", "perixa_billing", ".")
shutil.rmtree("test", ignore_errors=True)
m = "android/app/src/main/AndroidManifest.xml"
s = open(m, encoding="utf-8").read()
if "android.permission.INTERNET" not in s:
    s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Perixa Billing"', s, count=1)
open(m, "w", encoding="utf-8").write(s)
run("flutter", "pub", "get")
run("dart", "run", "flutter_launcher_icons")
print("Android project ready. Now run: flutter build apk --release")
