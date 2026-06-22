select *
from {{ ref('mart_daily_performance') }}
where aov < 0