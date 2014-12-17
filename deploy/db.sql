CREATE TABLE instructors (
    id                         VARCHAR(200) NOT NULL,
    serialized                 BLOB         NOT NULL,
    _activation_code_for_user  VARCHAR(32)  NOT NULL DEFAULT '',
    _activation_code_for_admin VARCHAR(32)  NOT NULL DEFAULT '',
    _autologin_code            VARCHAR(32)  NOT NULL DEFAULT '',
    
    INDEX (_activation_code_for_user),
    INDEX (_activation_code_for_admin),
    INDEX (_autologin_code),
    
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE students (
    id                         VARCHAR(200) NOT NULL,
    serialized                 BLOB         NOT NULL,
    is_enabled_leaderboard     VARCHAR(1)   NOT NULL DEFAULT '',
    _activation_code_for_user  VARCHAR(32)  NOT NULL DEFAULT '',
    _activation_code_for_admin VARCHAR(32)  NOT NULL DEFAULT '',
    _autologin_code            VARCHAR(32)  NOT NULL DEFAULT '',
    
    INDEX (is_enabled_leaderboard),
    INDEX (_activation_code_for_user),
    INDEX (_activation_code_for_admin),
    INDEX (_autologin_code),
    
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE students_results (
    id          VARCHAR(200) NOT NULL,
    student_id  VARCHAR(200) NOT NULL,
    submit_time INT UNSIGNED NOT NULL,
    serialized  BLOB         NOT NULL,

    INDEX (student_id),
    INDEX (submit_time),

    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
