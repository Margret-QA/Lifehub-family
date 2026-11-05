# LifeHub V5 — Real Accounts and Private Families

## What is new
- Email/password registration and login with Supabase Auth (email is the username for login).
- Login session persists across refreshes using Supabase Auth, **not** by saving plaintext passwords.
- Each account can create **multiple families** and rename each family.
- Database Row Level Security (RLS) prevents accounts outside a household from reading its details.
- New family profiles with emoji or small photo, assigned tasks, bills, groceries and school events.
- Edit/delete tasks, optional amounts, recurring reminder settings, green upcoming/red overdue/purple long-overdue badges.
- Mobile-responsive PWA layout and dashboard with per-person counts.

## Setup (required before login works)
1. Create a free Supabase project at https://supabase.com/dashboard.
2. In **SQL Editor**, paste and run the complete `schema.sql` once on a new project.
3. In **Authentication > Providers**, enable Email. For a public site, leave email confirmation enabled and configure a suitable email provider/redirect URL.
4. Open `config.js` and replace `YOUR_PROJECT` and `YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY` with your Project URL and **publishable/anon** key from Project Settings > API. NEVER use a service_role or secret key in frontend code.
5. Serve folder over HTTP using VS Code Live Server or `python -m http.server 8000`, then open the local URL. For public deployment use HTTPS hosting and configure Supabase Authentication URL settings.
6. Click **Create a new account**, confirm email if required, log in, and click **Create my family**. You can then create more families using **+ New family**.

## Important access model
- **Real login is enabled** once Supabase is configured. Each family creator is its administrator. Other accounts cannot access that family through the database.
- **Family profiles are not separate login accounts.** Secure invitations that allow multiple real users to join the *same* family are NOT implemented in V5. This requires an invitation and verification flow and is planned for V6.
- `household_members` supports future shared access, but V5 deliberately does not expose membership creation to the browser.
- Only the administrator can create/edit/complete items in V5. The family dashboard shows responsibility by profile.
- Supabase Auth remembers the session, **not the password**. Users may use their browser's password manager to remember passwords.
- Photos are saved as small base64 data in the database for prototype simplicity; production should use private object storage and authorization policies.
- Reminder timing and repeat intervals are saved but **background push delivery is not implemented**. A secure server-side scheduler is needed.
- The calendar currently displays the current month. Add month navigation and recurring occurrence generation in a future version.
- This is an implementation starter, **not an audited production service**. Conduct RLS cross-account tests, accessibility and security review before inviting public users.

## Quick privacy verification
1. Create Account A and Family A with a task.
2. Sign out and create Account B. Account B must see no Family A data.
3. Account B creates Family B; it must see only Family B.
4. Sign back in as Account A; only Family A appears.
5. Create a second family as Account A and switch between them; their items remain separate.

## Files
- `index.html` / `style.css` / `app.js`: application.
- `schema.sql`: Supabase database, RLS policies, and atomic family creation function.
- `config.js`: local Supabase public settings (placeholders until configured).
- `manifest.webmanifest`, `icon.svg`, `sw.js`: PWA foundation. The worker is intentionally not auto-registered until authenticated caching behavior is fully tested.
