# תיקון אימות Supabase — גרסה 1.2.1

ב-Supabase:
Authentication > URL Configuration

1. Site URL = כתובת GitHub Pages המדויקת של האפליקציה.
2. Redirect URLs = הוסף את אותה כתובת.
3. מומלץ להוסיף גם:
   https://USERNAME.github.io/REPOSITORY/**

לאחר מכן העלה ל-GitHub Pages את כל הקבצים מתוך ה-ZIP החדש, במיוחד:
- index.html
- cloud.js
- manifest.webmanifest
- sw.js
- icon.svg

אם כבר יצרת משתמש והמייל הקודם נכשל:
1. פתח את האפליקציה החדשה.
2. כניסה לענן.
3. הזן את האימייל.
4. לחץ "שלח שוב מייל אימות".
5. השתמש במייל החדש ביותר.
6. לאחר שהאימות מצליח, התחבר.

רק לאחר שמופיע בראש האפליקציה "מסונכרן" צפויות להיווצר הרשומות
ב-households וב-household_members, ולאחר הזנת נתונים גם בשאר הטבלאות.
