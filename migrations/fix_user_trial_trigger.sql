-- 修复用户举报公审系统
-- 1. 为 user_reports 表添加触发器，举报≥2次自动创建公审
-- 2. 添加超级管理员直接处理用户的函数
-- 3. 确保 user_trials 表有 ban_reason 字段
-- 4. 更新超级管理员判断函数，添加新管理员
-- 5. 修复 get_active_user_trials 函数，返回 status 字段

-- 1. 确保 user_trials 表有 ban_reason 字段
ALTER TABLE user_trials ADD COLUMN IF NOT EXISTS ban_reason TEXT;

-- 2. 更新超级管理员判断函数（添加新管理员邮箱）
CREATE OR REPLACE FUNCTION is_super_admin(check_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    user_email TEXT;
    user_phone TEXT;
BEGIN
    -- 获取用户邮箱
    SELECT email INTO user_email FROM auth.users WHERE id = check_user_id;

    -- 检查邮箱是否为超级管理员
    IF user_email IN ('2211354141@qq.com', '19256680343@bigblue.com', '13590179040@bigblue.com') THEN
        RETURN TRUE;
    END IF;

    -- 兼容旧的手机号判断
    SELECT raw_user_meta_data->>'phone' INTO user_phone
    FROM auth.users
    WHERE id = check_user_id;

    IF user_phone = '19256680343' THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 更新 get_active_user_trials 函数，添加 status 和 ban_reason 字段
DROP FUNCTION IF EXISTS get_active_user_trials();
CREATE OR REPLACE FUNCTION get_active_user_trials()
RETURNS TABLE (
    trial_id UUID,
    target_user_id UUID,
    target_username TEXT,
    target_avatar_url TEXT,
    target_bio TEXT,
    report_count BIGINT,
    ban_count INT,
    innocent_count INT,
    status TEXT,
    ban_reason TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ut.trial_id,
        ut.target_user_id,
        p.username,
        p.avatar_url,
        p.bio,
        (SELECT COUNT(*) FROM user_reports ur WHERE ur.target_user_id = ut.target_user_id),
        ut.ban_count,
        ut.innocent_count,
        ut.status,
        ut.ban_reason,
        ut.resolved_at,
        ut.created_at
    FROM user_trials ut
    LEFT JOIN profiles p ON p.id = ut.target_user_id
    WHERE ut.status = 'active'
    ORDER BY ut.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 更新 check_and_create_user_trial 函数（确保正确）
-- 先删除触发器，再删除函数
DROP TRIGGER IF EXISTS trigger_auto_create_user_trial ON user_reports;
DROP FUNCTION IF EXISTS check_and_create_user_trial();
CREATE OR REPLACE FUNCTION check_and_create_user_trial()
RETURNS TRIGGER AS $$
BEGIN
    -- 检查该用户是否被举报≥2次，且没有活跃的公审
    IF (SELECT COUNT(*) FROM user_reports WHERE target_user_id = NEW.target_user_id) >= 2 THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_trials
            WHERE target_user_id = NEW.target_user_id AND status = 'active'
        ) THEN
            INSERT INTO user_trials (target_user_id, status) VALUES (NEW.target_user_id, 'active');
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. 创建触发器：用户举报后自动检查是否需要公审
DROP TRIGGER IF EXISTS trigger_auto_create_user_trial ON user_reports;
CREATE TRIGGER trigger_auto_create_user_trial
AFTER INSERT ON user_reports
FOR EACH ROW
EXECUTE FUNCTION check_and_create_user_trial();

-- 6. 超级管理员处理用户公审（封禁或释放）
DROP FUNCTION IF EXISTS resolve_user_trial(UUID, UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION resolve_user_trial(
    p_trial_id UUID,
    p_admin_user_id UUID,
    p_status TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    trial_record RECORD;
BEGIN
    -- 验证超级管理员权限
    IF NOT is_super_admin(p_admin_user_id) THEN
        RETURN jsonb_build_object('success', false, 'error', '无权限');
    END IF;

    -- 检查公审是否存在
    SELECT * INTO trial_record FROM user_trials WHERE trial_id = p_trial_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', '公审不存在');
    END IF;

    -- 更新公审状态
    UPDATE user_trials
    SET status = p_status,
        ban_reason = CASE WHEN p_status = 'banned' THEN p_reason ELSE NULL END,
        resolved_at = NOW()
    WHERE trial_id = p_trial_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. 检查现有被举报用户是否有需要创建公审的
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT ur.target_user_id, COUNT(*) as cnt
        FROM user_reports ur
        WHERE ur.target_user_id NOT IN (
            SELECT ut.target_user_id FROM user_trials ut WHERE ut.status = 'active'
        )
        GROUP BY ur.target_user_id
        HAVING COUNT(*) >= 2
    LOOP
        INSERT INTO user_trials (target_user_id, status) VALUES (r.target_user_id, 'active')
        ON CONFLICT DO NOTHING;
        RAISE NOTICE '为用户 % 创建了公审', r.target_user_id;
    END LOOP;
END $$;