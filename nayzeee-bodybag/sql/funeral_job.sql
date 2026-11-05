-- nayzeee-bodybag: the Funeral Home job for ESX
-- Run ONCE, then restart the server (ESX loads jobs on start).
-- Grade numbers match Config.Funeral.Grades (0 trainee ... 3 director).

INSERT IGNORE INTO `jobs` (`name`, `label`) VALUES ('funeral', 'Funeral Home');

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
SELECT * FROM (
    SELECT 'funeral' AS job_name, 0 AS grade, 'trainee'   AS name, 'Trainee'          AS label, 150 AS salary, '{}' AS skin_male, '{}' AS skin_female UNION ALL
    SELECT 'funeral', 1, 'mortician', 'Mortician',        250, '{}', '{}' UNION ALL
    SELECT 'funeral', 2, 'senior',    'Senior Mortician', 350, '{}', '{}' UNION ALL
    SELECT 'funeral', 3, 'boss',      'Funeral Director', 500, '{}', '{}'
) AS grades
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'funeral');
