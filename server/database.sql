create table if not exists users (
	id serial primary key,
	full_name varchar(50) not null check (full_name <> ''),
	username varchar(30) not null check (username <> '') unique,
	passw text not null check (passw <> ''),
	date_joined date not null,
	last_login timestamp
);