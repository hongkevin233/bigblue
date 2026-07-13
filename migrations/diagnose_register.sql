-- 诊断注册失败问题
-- 请在 Supabase SQL Editor 中执行

-- 1. 检查 profiles 表是否有 username '2222'
SELECT id, username, email FROM profiles WHERE username = '2222';

-- 2. 检查 profiles 表结构
SELECT column_name, data_type, is_nullable, column_default 
FROM information_schema.columns 
WHERE table_name = 'profiles' 
ORDER BY ordinal_position;

-- 3. 检查 profiles 表的约束
SELECT conname, contype, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'profiles'::regclass;

-- 4. 检查触发器是否存在
SELECT tgname, pg_get_triggerdef(oid) 
FROM pg_trigger 
WHERE tgrelid = 'auth.users'::regclass;

-- 5. 检查 handle_new_user 函数是否存在
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'handle_new_user';

-- 6. 检查最近注册失败的用户（auth.users 表）
SELECT id, email, raw_user_meta_data, created_at 
FROM auth.users 
ORDER BY created_at DESC 
LIMIT 5;