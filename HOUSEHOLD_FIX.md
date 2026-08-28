# תיקון 42501 — יצירת Household

השגיאה:
`new row violates row-level security policy for table "households"`

היא אומרת שהמשתמש מחובר, אבל RLS חוסם את יצירת המשפחה הראשונה.

## מה עושים
1. Supabase > SQL Editor
2. הרץ את `supabase_household_bootstrap_fix.sql`
3. העלה ל-GitHub Pages את קבצי גרסה 1.2.3
4. התחבר מחדש לאפליקציה
5. בדוק:
   - households: שורה אחת
   - household_members: שורה אחת
6. הוסף עסקת ניסיון ובדוק שהיא מופיעה ב-transactions

בגרסה הזו יצירת המשפחה הראשונה נעשית דרך RPC מאובטח בצד השרת,
ולא דרך INSERT רגיל שנחסם על-ידי RLS.
