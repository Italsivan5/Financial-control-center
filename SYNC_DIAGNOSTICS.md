# Supabase Sync Diagnostics 1.2.2

1. ב-Supabase פתח SQL Editor.
2. הרץ `supabase_rls_repair_v12.sql`.
3. בתוצאת ה-SELECT הראשון כל עמודות הטבלאות צריכות להכיל שם טבלה, לא NULL.
4. העלה את קבצי 1.2.2 ל-GitHub Pages.
5. התחבר לאפליקציה.
6. אם עדיין יש תקלה, הבאנר הכתום יציג את קוד והודעת Supabase המקוריים במקום הודעה כללית.

הקובץ מנקה Policies ישנים שעלולים לגרום לרקורסיית RLS ומבקש מ-PostgREST לרענן את schema cache.
