# Testowe pushe forka (symulator)

Format jest ten sam, który wysyła `oc-apns` z hosta Gatewaya: `aps` + klucz `openclaw.fork` (`sessionKey`, `kind`, `pr`).

```
xcrun simctl push booted <bundle id aplikacji> question.apns
```

`<bundle id>` to bundle Twojej aplikacji (w buildzie Debug z końcówką `.debug`). Bez niego `simctl` weźmie
`Simulator Target Bundle` z pliku. Tapnięcie otwiera wątek agenta w modalu. Długie przytrzymanie pokazuje
akcje: „Odpowiedz” (tekst albo dyktowanie, także na zegarku), „Otwórz” i — przy PR — „Zmerdżuj”.
