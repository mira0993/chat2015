import os.path
import json

from tornado import ioloop, web
import settings, utils


class BaseHandler(web.RequestHandler):
    def get_json(self):
        try:
            _json = json.loads(self.request.body.decode('utf-8'))
            return _json
        except Exception:
            self.write('Bad format')
            self.finish()


class IndexHandler(BaseHandler):
    def get(self):
        self.write("It's running")


class CreateUserHandler(BaseHandler):
    QUERY = """create table if not exists messages_{0} (
        id bigserial primary key,
        received_from int references users(id) not null,
        msg text not null check (msg <> ''),
        send_at timestamp not null);"""

    def post(self):
        _json = self.get_json()
        passwd = utils.encrypt_password(_json['password'])
        with utils.DBConnection() as (con, cur):
            try:
                cur.execute(("insert into users (full_name, username, passw, date_joined) "
                             "values (%s, %s, %s, CURRENT_TIMESTAMP)"),
                            (_json['full_name'], _json['username'], passwd))
                cur.execute("select id from users where username = %s", (_json['username'],))
                row = cur.fetchone()
                cur.execute(CreateUserHandler.QUERY.format(row[0]))
                con.commit()
                self.write("OK")
            except Exception as e:
                self.write(utils.get_output_msg("ERROR: Unable to create the user"), e)


class DeleteUserHandler(BaseHandler):
    def post(self):
        _json = self.get_json()
        with utils.DBConnection() as (con, cur):
            try:
                cur.execute("select id from users where username = %s", (_json["username"],))
                user_id = cur.fetchone()[0]
                cur.execute("delete from users where id = %s", (user_id,))
                cur.execute("drop table messages_{0} cascade".format(user_id))
                con.commit()
                self.write("OK")
            except Exception as e:
                self.write(utils.get_output_msg("ERROR: Unable to delete the user", e))


class GetUserList(BaseHandler):
    def get(self):
        with utils.DBConnection() as (con, cur):
            try:
                filt = "%{0}%".format(self.get_argument("filter", ""))
                cur.execute("select full_name, username from users where username LIKE %s",
                            (filt,))
                response = list()
                for user in cur.fetchall():
                    response.append({"full_name": user[0], "username": user[1]})
                self.write(json.dumps(response))
                con.commit()
            except Exception as e:
                self.write(utils.get_output_msg("ERROR: Unable to fetch user list", e))


class InitDBHandler(BaseHandler):
    def post(self):
        with utils.DBConnection() as (con, cur):
            try:
                cur.execute("drop schema if exists public cascade")
                cur.execute("create schema public authorization {0}".format(settings.DB_USER))
                # Ambiguos character at begining
                script = open("server/database.sql", encoding='utf-8').read()[1:]
                cur.execute(script)
                con.commit()

                self.write('OK')
            except Exception as e:
                self.write(utils.get_output_msg("ERROR: Unable to initialize DB", e))


def main():
    handlers = [
        (r'/', IndexHandler),
        (r'/Users/Create/', CreateUserHandler),
        (r'/Users/Delete/', DeleteUserHandler),
        (r'/Users/List/', GetUserList),
    ]
    if settings.DEBUG:
        handlers.append((r'/Test/Init/', InitDBHandler))
    app = web.Application(handlers, debug=True)
    app.listen(8000)
    ioloop.IOLoop.instance().start()

if __name__ == '__main__':
    main()