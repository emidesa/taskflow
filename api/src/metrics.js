// Métriques Prometheus de l'API : méthode RED (Rate, Errors, Duration)
// + une métrique métier. Chaque appel crée SON registre (pas le global) :
// chaque test peut créer une application neuve sans conflit de noms.
import client from 'prom-client';

// Route Express (/api/tasks/:id/toggle), jamais l'URL réelle (/api/tasks/42/toggle) :
// sinon une nouvelle série par identifiant -> explosion de la cardinalité.
function routeLabel(req, res) {
  if (!req.route) return 'unmatched';
  // En cas d'erreur, Express a déjà vidé req.baseUrl : on prend celui retenu par le routeur
  const route = `${res.locals.baseUrl ?? req.baseUrl}${req.route.path}`;
  return route.length > 1 ? route.replace(/\/$/, '') : route;
}

export function createMetrics({ appVersion, collectDefaults = true }) {
  const register = new client.Registry();
  const labelNames = ['method', 'route', 'status_code'];

  const requests = new client.Counter({
    name: 'http_requests_total',
    help: 'Nombre de requêtes HTTP',
    labelNames,
    registers: [register],
  });

  const duration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Durée des requêtes HTTP en secondes',
    labelNames,
    registers: [register],
  });

  const tasksCreated = new client.Counter({
    name: 'taskflow_tasks_created_total',
    help: 'Nombre de tâches créées',
    registers: [register],
  });

  const buildInfo = new client.Gauge({
    name: 'taskflow_build_info',
    help: "Version de l'API en ligne (toujours 1)",
    labelNames: ['version'],
    registers: [register],
  });
  buildInfo.set({ version: appVersion }, 1);

  if (collectDefaults) client.collectDefaultMetrics({ register });

  function middleware(req, res, next) {
    const stopTimer = duration.startTimer();
    // Les labels sont calculés à la fin : req.route n'est connu qu'après le routage
    res.on('finish', () => {
      const labels = {
        method: req.method,
        route: routeLabel(req, res),
        status_code: String(res.statusCode),
      };
      requests.inc(labels);
      stopTimer(labels);
    });
    next();
  }

  async function handler(_req, res) {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  }

  return {
    register,
    middleware,
    handler,
    taskCreated: () => tasksCreated.inc(),
  };
}
