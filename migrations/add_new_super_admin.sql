-- 新增超级管理员 13590179040@bigblue.com
-- 请在 Supabase SQL Editor 中执行此文件

-- 更新 is_super_admin 函数，添加新的超管邮箱
CREATE OR REPLACE FUNCTION is_super_admin(check_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    user_email TEXT;
    user_phone TEXT;
    profile_phone TEXT;
BEGIN
    -- 从 auth.users 获取邮箱
    SELECT email INTO user_email FROM auth.users WHERE id = check_user_id;
    
    -- 检查邮箱是否为超级管理员
    IF user_email IN ('2211354141@qq.com', '19256680343@bigblue.com', '13590179040@bigblue.com') THEN
        RETURN TRUE;
    END IF;
    
    -- 兼容旧的手机号判断
    SELECT raw_user_meta_data->>'phone' INTO user_phone FROM auth.users WHERE id = check_user_id;
    SELECT phone INTO profile_phone FROM profiles WHERE id = check_user_id;
    
    RETURN COALESCE(user_phone, profile_phone, '') = '19256680343';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;