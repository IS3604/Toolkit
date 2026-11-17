EDITSIMPLE TOOLKIT — SETUP (keys already added)

1. Supabase > SQL Editor > paste schema.sql > Run
2. Authentication > Users > Add user (your email + password)
3. SQL Editor > run (change the email):
   insert into public.admins(user_id) select id from auth.users where email = 'you@editsimple.in';
4. Upload index.html to GitHub Pages / Vercel / Netlify. Done.

Add tools: open site > Admin (top right) > sign in > Add resource.
