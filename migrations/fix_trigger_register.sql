-- 修复注册失败的触发器问题
-- 请在 Supabase SQL Editor 中执行此文件

-- 1. 删除旧触发器和函数
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

-- 2. 创建新的触发器函数（更健壮的版本）
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- 使用更简单的方式生成唯一用户名：nickname + UUID 前8位
    -- 这样几乎不可能重复
    INSERT INTO profiles (id, username, email, bio, followers_count, following_count)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data->>'nickname',
            NEW.raw_user_meta_data->>'username',
            '用户'
        ) || '_' || substr(NEW.id::text, 1, 8),
        NEW.email,
        '',
        0,
        0
    )
    ON CONFLICT (id) DO UPDATE SET
        username = COALESCE(NEW.raw_user_meta_data->>'nickname', profiles.username),
        email = COALESCE(NEW.email, profiles.email);
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- 如果插入失败，记录错误但不阻止用户创建
    RAISE WARNING '创建 profile 失败: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 创建触发器
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 4. 检查 auth.users 表中是否有失败的注册尝试，为它们创建 profile
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