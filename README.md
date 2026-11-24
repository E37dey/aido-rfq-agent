# aido-rfq-agent

סוכן AI שמכין הצעות מחיר למפעל לעיבוד שבבי, על Claude Managed Agents. שיעורי בית, AiDO שיעור 6.

לקוח שולח מייל ושרטוט. הסוכן קורא את השרטוט, מתמחר לפי המחירון של המפעל, בודק מה הוצע ללקוח בעבר, ומחזיר לבעל המפעל טיוטה: הצעת מחיר ב-Excel, מייל תשובה ורשימת שאלות. סתירות ופרטים חסרים לא נפתרים בשקט, הם הופכים לשאלות. בין ריצה לריצה הסוכן זוכר לקוחות והצעות, ב-memory store.

הנתונים סינתטיים: המחירון, הלקוחות והשרטוטים בדויים.

## המסמכים

- [SPEC.md](SPEC.md): מה הסוכן עושה, הכלים, הזיכרון, המעקות והבדיקה.
- [Architecture.md](Architecture.md): תרשימי זרימה, הזיכרון בין ריצות, וגרסת הפיילוט.

## מה יש בריפו

| נתיב | מה זה |
|---|---|
| `templates/agent-rfq-quoter.json` | הסוכן: מודל, תיאור תפקיד, כלים והרשאות, skill |
| `templates/env-rfq-offline.json` | הסביבה: container בענן, בלי רשת |
| `templates/store-*.json` | שני ה-memory stores: מחירון (קריאה בלבד) והיסטוריה (קריאה וכתיבה) |
| `templates/session-rfq.json` | ה-session: stores, תקציב, outcome עם rubric |
| `templates/deployment-followup.planned.json` | הרצה שבועית למעקב הצעות (מתוכנן) |
| `seed/` | התוכן ההתחלתי של שני ה-stores |
| `demo/rfq-001`, `demo/rfq-002` | שתי בקשות סינתטיות מאותו לקוח: מייל ושרטוט |
| `demo/ground-truth.md` | מה הסוכן צריך לזהות בכל בקשה, נכתב לפני ההרצה |
| `scripts/` | הקמה חד-פעמית, והרצה של בקשה אחת |
| `runs/` | תוצאות ההרצות |

## הרצה

צריך מפתח API עם גישה ל-Managed Agents (beta). הסקריפט קורא אותו ממשתנה הסביבה `ANTHROPIC_API_KEY`, או מבקש אותו בקלט מוסתר. המפתח לא נשמר בקובץ.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-rfq-agent.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\run-rfq.ps1 -RfqDir .\demo\rfq-001
powershell -ExecutionPolicy Bypass -File .\scripts\run-rfq.ps1 -RfqDir .\demo\rfq-002
```

את הבקשות מריצים לפי הסדר: השנייה בודקת שהסוכן זוכר את מה שכתב בראשונה.
