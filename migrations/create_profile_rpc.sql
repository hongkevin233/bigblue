-- 创建一个 RPC 函数供前端调用，用于创建用户 profile
-- 请在 Supabase SQL Editor 中执行此文件

CREATE OR REPLACE FUNCTION create_user_profile(p_user_id UUID, p_username TEXT, p_email TEXT)
RETURNS void AS $$
BEGIN
    INSERT INTO profiles (id, username, email, bio, followers_count, following_count)
    VALUES (p_user_id, p_username, p_email, '', 0, 0)
    ON CONFLICT (id) DO UPDATE SET
        username = COALESCE(p_username, profiles.username),
        email = COALESCE(p_email, profiles.email);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 为所有缺失 profile 的用户创建 profile
INSERT INTO profiles (id, username, email, bio, followers_count, following_count)
SELECT 
    u.id,
    COALESCE(u.raw_user_meta_data->>'nickname', u.raw_user_meta_data->>'username', '用户') || '_' || substr(u.id::text, 1, 8),
    u.email,
    '',
    0,
    0
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = u.id)
ON CONFLICT (id) DO NOTHING;

-- 检查结果
SELECT '修复后缺失 profile 的用户' as type, COUNT(*) as count
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = u.id);