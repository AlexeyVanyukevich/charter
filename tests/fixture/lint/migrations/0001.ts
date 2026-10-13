interface Kysely<T> {
  schema: T
}

export function up(db: Kysely<any>): void {
  void db
}
