# sql-command.nvim

Simple plugin to run SQL command (for MariaDB).
It allows to run command from a selection or for the current line.

It uses MariaDB command (so it works only if the MariaDB client is installed).

> [!WARNING]
> This is very WIP project. I did it for myself, but it might be useful for
> others. And use it with caution

## Usage

Basic usage:

1. Select SQL command
2. Go to command mode `:`
3. You should see: `:'<,'>`
4. Type `SQL` and hit `<Enter>` you should have in command something like this:
   `:'<,'>SQL`

In this scenario SQL Command will be passed to mariadb client for the database
declared in the config file. (`<YourProjectPath>/.db.json`)

If you want to run a query from different database use: `:SQL <database_name>`

This will open a "floated" window with query result. This window will also contain
executed query. You can adjust query and run it again.

So the `.db.json` example:

```json
{
  "database": "mydb"
}
```

## Known restrictions

- For now it connects to local MariaDB server using `user's name` declared
  in `~/.my.cnf` I do have plan to make this more configurable.
- Password is now also stored in `~/.my.cnf`. This also is planned to be added
  in the nearest future.

As I said I made this to be able simply run query directly from nvim in nvim
from selection.

## TODO

- [ ] Add to config - user, password
- [ ] Add to config and command parameters style: markdown | simple
- [ ] Add some screenshots
