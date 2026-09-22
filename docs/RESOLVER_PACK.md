# POTV Resolver Pack v1

Un Resolver Pack es un paquete local que permite transportar resolvers HTTP compatibles con el protocolo POTV y addons Stremio/Nuvio entre dispositivos sin recompilar la aplicación.

```json
{
  "format": "potv-resolver-pack",
  "version": 1,
  "http_sources": [
    {
      "id": "resolver-demo",
      "name": "Resolver autorizado",
      "endpoint": "https://resolver.example/resolve",
      "enabled": true
    }
  ],
  "stremio_addons": [
    {
      "id": "addon-demo",
      "name": "Addon compatible",
      "manifest_uri": "https://addon.example/manifest.json",
      "enabled": true
    }
  ]
}
```

Los endpoints repetidos se deduplican por URL. El pack no contiene historial, cuentas ni credenciales de POTV.
