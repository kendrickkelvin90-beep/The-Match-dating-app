CREATE OR REPLACE FUNCTION private.preference_accepts_gender(p_preference text,p_gender text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE
 WHEN lower(trim(coalesce(p_preference,''))) IN ('all genders','tous les genres','everyone','all') THEN true
 WHEN lower(trim(coalesce(p_preference,''))) IN ('men and women','men & women','both men and women','men, women') THEN lower(trim(coalesce(p_gender,''))) IN ('man','men','male','homme','trans man','transmasculine','woman','women','female','femme','trans woman','transfeminine')
 WHEN lower(trim(coalesce(p_preference,''))) IN ('men','male','man','homme') THEN lower(trim(coalesce(p_gender,''))) IN ('man','men','male','homme','trans man','transmasculine')
 WHEN lower(trim(coalesce(p_preference,''))) IN ('women','woman','female','femme') THEN lower(trim(coalesce(p_gender,''))) IN ('woman','women','female','femme','trans woman','transfeminine')
 ELSE false END;
$$;