-- 完整修复 profiles 表结构、触发器、RLS 策略
-- 请在 Supabase SQL Editor 中执行此文件

-- 1. 确保 profiles 表有所有必要字段
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS followers_count INTEGER DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS following_count INTEGER DEFAULT 0;

-- 2. 重新创建触发器（使用 SECURITY DEFINER）
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, username, email, bio, followers_count, following_count)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data->>'nickname',
            NEW.raw_user_meta_data->>'username',
            '用户_' || substr(NEW.id::text, 1, 8)
        ),
        NEW.email,
        '',
        0,
        0
    )
    ON CONFLICT (id) DO UPDATE SET
        username = COALESCE(NEW.raw_user_meta_data->>'nickname', NEW.raw_user_meta_data->>'username', profiles.username),
        email = COALESCE(NEW.email, profiles.email);
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '创建 profile 失败: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 3. 确保 RLS 策略正确
DROP POLICY IF EXISTS "所有人可查看用户资料" ON profiles;
DROP POLICY IF EXISTS "用户可更新自己的资料" ON profiles;
DROP POLICY IF EXISTS "用户可插入自己的资料" ON profiles;
DROP POLICY IF EXISTS "用户可删除自己的资料" ON profiles;

CREATE POLICY "所有人可查看用户资料" ON profiles FOR SELECT USING (true);
CREATE POLICY "用户可更新自己的资料" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "用户可插入自己的资料" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "用户可删除自己的资料" ON profiles FOR DELETE USING (auth.uid() = id);

-- 4. 确保 posts 表 RLS 策略正确
DROP POLICY IF EXISTS "所有人可查看笔记" ON posts;
DROP POLICY IF EXISTS "登录用户可发布笔记" ON posts;
DROP POLICY IF EXISTS "用户可更新自己的笔记" ON posts;
DROP POLICY IF EXISTS "用户可删除自己的笔记" ON posts;

CREATE POLICY "所有人可查看笔记" ON posts FOR SELECT USING (true);
CREATE POLICY "登录用户可发布笔记" ON posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "用户可更新自己的笔记" ON posts FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "用户可删除自己的笔记" ON posts FOR DELETE USING (auth.uid() = user_id);

-- 5. 确保 comments 表 RLS 策略正确
DROP POLICY IF EXISTS "所有人可查看评论" ON comments;
DROP POLICY IF EXISTS "登录用户可评论" ON comments;
DROP POLICY IF EXISTS "用户可删除自己的评论" ON comments;

CREATE POLICY "所有人可查看评论" ON comments FOR SELECT USING (true);
CREATE POLICY "登录用户可评论" ON comments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "用户可删除自己的评论" ON comments FOR DELETE USING (auth.uid() = user_id);

-- 6. 为所有缺失 profile 的用户创建 profile
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

-- 7. 检查结果
SELECT 'profiles 表结构' as info;
SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'profiles';

SELECT 'auth.users 数量' as type, COUNT(*) as count FROM auth.users;
SELECT 'profiles 数量' as type, COUNT(*) as count FROM profiles;
SELECT '缺失 profile 的用户' as type, COUNT(*) as count FROM auth.users u WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = u.id);