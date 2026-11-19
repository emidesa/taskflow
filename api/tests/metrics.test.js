// Tests des métriques Prometheus : format, normalisation des routes, erreurs.
import request from 'supertest';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { createMetrics } from '../src/metrics.js';
import { createMemoryRepository } from '../src/repositories/memory.js';

// collectDefaults: false : on ne garde que nos métriques (sortie plus lisible)
function buildApp(repository = createMemoryRepository()) {
  const log = vi.fn();
  const metrics = createMetrics({
    appVersion: '1.2.3',
    collectDefaults: false,
  });
  const app = createApp({ repository, log, metrics });
  return { app, log };
}

describe('GET /metrics', () => {
  let app;
  let log;

  beforeEach(() => {
    ({ app, log } = buildApp());
  });

  it('répond 200 au format texte de Prometheus', async () => {
    const response = await request(app).get('/metrics');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/text\/plain/);
    expect(response.text).toContain('taskflow_build_info{version="1.2.3"} 1');
  });

  it("utilise la route Express, jamais l'URL réelle", async () => {
    await request(app).post('/api/tasks').send({ title: 'Une tâche' });
    await request(app).patch('/api/tasks/1/toggle');

    const { text } = await request(app).get('/metrics');

    expect(text).toContain('route="/api/tasks"');
    expect(text).toContain('route="/api/tasks/:id/toggle"');
    expect(text).not.toContain('/api/tasks/1');
    expect(text).toContain('taskflow_tasks_created_total 1');
  });

  it('compte une URL inconnue sous unmatched', async () => {
    await request(app).get('/nexiste/pas');

    const { text } = await request(app).get('/metrics');

    expect(text).toContain('route="unmatched",status_code="404"');
  });

  it("n'appelle pas le logger", async () => {
    await request(app).get('/metrics');

    expect(log).not.toHaveBeenCalled();
  });
});

describe('Erreurs serveur', () => {
  it('compte une réponse 500', async () => {
    const repository = {
      ...createMemoryRepository(),
      list: () => Promise.reject(new Error('base injoignable')),
    };
    const { app } = buildApp(repository);

    await request(app).get('/api/tasks');
    const { text } = await request(app).get('/metrics');

    expect(text).toContain(
      'http_requests_total{method="GET",route="/api/tasks",status_code="500"} 1',
    );
  });
});
