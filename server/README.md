#Chat 2015
--------

Distributed Systems Project

###Creating virtual environment (archlinux)
-----

1. Run the following commands:

        sudo pacman -S python-virtualenv
        
2. Cd into your project dir and run the following:

        virtualenv3 .venv
        source .venv/bin/activate
        pip install -r requirements.txt

###Installing postgresql (archlinux)
-----

1. Run the following commands:

        sudo pacman -S postgresql
        sudo -i -u postgres
        initdb --locale en_US.UTF-8 -E UTF8 -D '/var/lib/postgres/data'
        
2. Run in another shell, but do not close the postgres shell:

        sudo systemctl start postgresql
        
3. Then, return to the postgres shell and run:

        createuser --interactive
        createdb chat
        psql
        alter user postgres with password '<NEW_PASSWORD>';
        alter user <USER_YOU_HAVE_JUST_CREATED> with password '<NEW_PASSWORD>';
        \q

