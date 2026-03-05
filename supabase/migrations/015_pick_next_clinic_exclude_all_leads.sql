-- Migration 015: Corrige pick_next_clinic() — exclui toda clínica já presente em gk_leads
-- Anteriormente excluía apenas status IN ('created', 'gathering_decisor'),
-- permitindo re-abordagem de leads com status 'failed', 'stalled', 'decisor_captured'.
-- Regra correta: qualquer clínica que já está em gk_leads (qualquer status) não deve
-- ser sorteada novamente — ela já foi ou está sendo abordada.

CREATE OR REPLACE FUNCTION public.pick_next_clinic()
RETURNS TABLE(
  out_place_id         TEXT,
  out_clinic_name      TEXT,
  out_clinic_phone     TEXT,
  out_lead_score       NUMERIC,
  out_ads_group        TEXT,
  out_google_ads_count INTEGER,
  out_google_reviews   INTEGER,
  out_google_rating    NUMERIC,
  out_selection_mode   TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_environment   TEXT;
    v_homolog_phone TEXT;

    v_total_scheduled INT;
    v_att_high INT; v_conv_high INT;
    v_att_mid  INT; v_conv_mid  INT;
    v_att_low  INT; v_conv_low  INT;

    v_epsilon        NUMERIC;
    v_exploit        BOOLEAN;
    v_selected_group TEXT;

    v_rate_high  NUMERIC;
    v_rate_mid   NUMERIC;
    v_rate_low   NUMERIC;
    v_rate_total NUMERIC;

    v_rand NUMERIC;
BEGIN

    SELECT environment, homolog_phone
    INTO v_environment, v_homolog_phone
    FROM sdr_config WHERE id = 1;

    SELECT
        COALESCE(SUM(st.conv), 0),
        COALESCE(SUM(st.att)  FILTER (WHERE st.grp = 'ads_high'), 0),
        COALESCE(SUM(st.conv) FILTER (WHERE st.grp = 'ads_high'), 0),
        COALESCE(SUM(st.att)  FILTER (WHERE st.grp = 'ads_mid'),  0),
        COALESCE(SUM(st.conv) FILTER (WHERE st.grp = 'ads_mid'),  0),
        COALESCE(SUM(st.att)  FILTER (WHERE st.grp = 'ads_low'),  0),
        COALESCE(SUM(st.conv) FILTER (WHERE st.grp = 'ads_low'),  0)
    INTO
        v_total_scheduled,
        v_att_high, v_conv_high,
        v_att_mid,  v_conv_mid,
        v_att_low,  v_conv_low
    FROM (
        SELECT
            CASE
                WHEN gas.ads_count >= 5 THEN 'ads_high'
                WHEN gas.ads_count >= 2 THEN 'ads_mid'
                ELSE 'ads_low'
            END AS grp,
            COUNT(sc.id)                                            AS att,
            COUNT(sc.id) FILTER (WHERE sc.status = 'scheduled')    AS conv
        FROM google_maps_signals gms
        JOIN google_ads_signals  gas ON gas.place_id = gms.place_id
        LEFT JOIN clinic_decisors   sc  ON sc.place_id  = gms.place_id
        WHERE gas.ads_count > 0
          AND (gms.is_franchise  IS NOT TRUE)   -- exclui franquias/redes
          AND (gms.is_ineligible IS NOT TRUE)   -- exclui categorias fora do ICP
        GROUP BY grp
    ) st;

    v_epsilon := GREATEST(0.20, 1.0 - (v_total_scheduled::NUMERIC / 50.0));
    v_exploit := (random() > v_epsilon);

    IF NOT v_exploit THEN
        v_rand := random();
        IF    v_rand < 0.333 THEN v_selected_group := 'ads_high';
        ELSIF v_rand < 0.667 THEN v_selected_group := 'ads_mid';
        ELSE                       v_selected_group := 'ads_low';
        END IF;
    ELSE
        v_rate_high  := v_conv_high::NUMERIC / GREATEST(v_att_high, 1);
        v_rate_mid   := v_conv_mid::NUMERIC  / GREATEST(v_att_mid,  1);
        v_rate_low   := v_conv_low::NUMERIC  / GREATEST(v_att_low,  1);
        v_rate_total := v_rate_high + v_rate_mid + v_rate_low;

        IF v_rate_total = 0 THEN
            v_rand := random();
            IF    v_rand < 0.333 THEN v_selected_group := 'ads_high';
            ELSIF v_rand < 0.667 THEN v_selected_group := 'ads_mid';
            ELSE                       v_selected_group := 'ads_low';
            END IF;
        ELSE
            v_rand := random() * v_rate_total;
            IF    v_rand < v_rate_high                THEN v_selected_group := 'ads_high';
            ELSIF v_rand < (v_rate_high + v_rate_mid) THEN v_selected_group := 'ads_mid';
            ELSE                                           v_selected_group := 'ads_low';
            END IF;
        END IF;
    END IF;

    RETURN QUERY
    WITH candidates AS (
        SELECT
            gms.place_id                AS c_place_id,
            gms.name                    AS c_clinic_name,
            gms.phone_e164              AS c_clinic_phone,
            ROUND(
                LN(gas.ads_count::NUMERIC + 1) / LN(901.0) * 35.0
                + COALESCE(gms.rating, 0) * LN(COALESCE(gms.reviews_count, 0)::NUMERIC + 1)
                  / (5.0 * LN(189.0)) * 55.0
                + CASE WHEN gms.website IS NOT NULL AND gms.website != ''
                       THEN 10.0 ELSE 0.0 END
            , 2)                        AS c_lead_score,
            CASE
                WHEN gas.ads_count >= 5 THEN 'ads_high'
                WHEN gas.ads_count >= 2 THEN 'ads_mid'
                ELSE 'ads_low'
            END                         AS c_ads_group,
            gas.ads_count               AS c_google_ads_count,
            gms.reviews_count           AS c_google_reviews,
            gms.rating                  AS c_google_rating
        FROM google_maps_signals gms
        JOIN google_ads_signals gas ON gas.place_id = gms.place_id
        WHERE gas.ads_count > 0
          AND gms.phone_e164 IS NOT NULL
          AND gms.phone_e164 != ''
          AND (gms.is_franchise  IS NOT TRUE)   -- exclui franquias/redes
          AND (gms.is_ineligible IS NOT TRUE)   -- exclui categorias fora do ICP
          AND gms.phone_e164 NOT IN (
              SELECT clinic_phone
              FROM gk_leads
              WHERE clinic_phone IS NOT NULL
          )
    )
    SELECT
        c.c_place_id,
        c.c_clinic_name,
        c.c_clinic_phone,
        c.c_lead_score,
        c.c_ads_group,
        c.c_google_ads_count,
        c.c_google_reviews,
        c.c_google_rating,
        CASE WHEN v_environment = 'homolog' THEN 'homolog'::TEXT
             WHEN v_exploit THEN 'exploit'::TEXT ELSE 'explore'::TEXT END
    FROM candidates c
    WHERE c.c_ads_group = v_selected_group
    ORDER BY (c.c_lead_score * POWER(random(), 0.5)) DESC
    LIMIT 1;

END;
$function$;
