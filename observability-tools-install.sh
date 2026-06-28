#!/bin/bash

echo "##################################"
echo "# observability-tools-install.sh #"
echo "##################################"

# --- Configurações ---
CLUSTER_NAME="observability-cluster"
KIND_CONFIG="./kind-config.yaml"

PROMETHEUS_MANIFEST="./.settings/prometheus-service.yaml"
GRAFANA_MANIFEST="./.settings/grafana-service.yaml"
OTEL_CONFIG_MANIFEST="./.settings/otel-collector-config.yaml"
OTEL_SERVICE_MANIFEST="./.settings/otel-collector-service.yaml"
OTEL_MONITOR_MANIFEST="./.settings/otel-collector-monitor.yaml"

LOKI_MANIFEST="./.settings/loki.yaml"
TEMPO_MANIFEST="./.settings/tempo.yaml"
MIMIR_MANIFEST="./.settings/mimir.yaml" # Novo manifesto do Mimir

K8S_CONTEXT="kind-$CLUSTER_NAME"

echo "🏗️ Iniciando Bootstrap da Infraestrutura..."

# 0. Sync clock (WSL2)
if grep -qi microsoft /proc/version; then
    echo "🕒 Sync WSL2 clock..."
    sudo ntpdate -s pool.ntp.org >/dev/null 2>&1 || true
fi

# 1. Cluster
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "☸️ Cluster já existe"
else
    echo "🚀 Criando cluster..."
    kind create cluster --config "$KIND_CONFIG" || exit 1
fi

kubectl config use-context "$K8S_CONTEXT"

# 2. Namespace
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# 3. Clean Helm leftovers
helm uninstall kube-stack -n observability 2>/dev/null || true
kubectl delete mutatingwebhookconfigurations --all 2>/dev/null || true
kubectl delete validatingwebhookconfigurations --all 2>/dev/null || true

# 🔥 AJUSTE 1: Limpeza agressiva e preventiva de cache do Mimir e Loki
# Isso evita o erro de "field not found" causado por ConfigMaps presos na memória do Kubelet
echo "🧹 Limpando deploys e ConfigMaps antigos para evitar cache corrompido..."
kubectl delete deployment mimir loki tempo grafana -n observability 2>/dev/null || true
kubectl delete configmap mimir-config loki-config tempo-config grafana-datasources -n observability 2>/dev/null || true

# 4. Prometheus
echo "📥 Prometheus..."
kubectl apply -f "$PROMETHEUS_MANIFEST" || exit 1

# 5. Grafana
echo "📥 Grafana..."
kubectl apply -f "$GRAFANA_MANIFEST" || exit 1

# 6. Loki
echo "📥 Loki..."
kubectl apply -f "$LOKI_MANIFEST" || exit 1

# 7. Tempo
echo "📥 Tempo..."
kubectl apply -f "$TEMPO_MANIFEST" || exit 1

# 7.1 Mimir
echo "📥 Mimir..."
kubectl apply -f "$MIMIR_MANIFEST" || exit 1

# 8. OTEL Config
echo "📥 OTEL Config..."
kubectl apply -f "$OTEL_CONFIG_MANIFEST" || exit 1

# 9. OTEL Collector
echo "📥 OTEL Collector..."
kubectl apply -f "$OTEL_SERVICE_MANIFEST" || exit 1

# 10. ServiceMonitor (não crítico)
echo "📥 ServiceMonitor OTEL..."
kubectl apply -f "$OTEL_MONITOR_MANIFEST" || true

# 11. Aguardar base
echo "⏳ Aguardando startup de segurança..."
sleep 5

echo "🕒 Prometheus..."
kubectl wait --for=condition=ready pod -l app=prometheus -n observability --timeout=120s || true

echo "🕒 Grafana..."
kubectl wait --for=condition=ready pod -l app=grafana -n observability --timeout=120s || true

echo "🕒 OTEL..."
kubectl wait --for=condition=ready pod -l app=otel-collector -n observability --timeout=120s || true

echo "🕒 Loki..."
kubectl wait --for=condition=ready pod -l app=loki -n observability --timeout=180s || true

echo "🕒 Tempo..."
kubectl wait --for=condition=ready pod -l app=tempo -n observability --timeout=180s || true

# AJUSTE 2: Garantir que o wait do Mimir use a sintaxe de container pronta caso demore a subir
echo "🕒 Mimir..."
kubectl wait --for=condition=ready pod -l app=mimir -n observability --timeout=180s || true

echo "--------------------------------------------------"
echo "📊 DEBUG MIMIR (se falhar, aqui está o erro real):"
kubectl get pods -n observability -l app=mimir
# AJUSTE 3: Garante o print do log correto especificando o container principal se travar
kubectl logs -n observability -l app=mimir -c mimir --tail=50 || true

echo "--------------------------------------------------"
echo "📊 DEBUG TEMPO (se falhar, aqui está o erro real):"
kubectl get pods -n observability -l app=tempo
kubectl logs -n observability -l app=tempo --tail=50 || true

echo "--------------------------------------------------"
echo "📊 DEBUG LOKI (se necessário):"
kubectl get pods -n observability -l app=loki
kubectl logs -n observability -l app=loki --tail=50 || true

echo "--------------------------------------------------"
echo "✅ OBSERVABILITY STACK COMPLETA"
echo ""
echo "Grafana:     http://localhost:3000"
echo "Prometheus:  http://localhost:9090"
echo "Mimir HTTP:  http://localhost:9009"
echo "OTLP gRPC:   localhost:4317"
echo "OTLP HTTP:   localhost:4318"
echo ""
echo "✔ Prometheus"
echo "✔ Grafana"
echo "✔ OTEL Collector"
echo "✔ Loki"
echo "✔ Tempo"
echo "✔ Mimir"
echo "--------------------------------------------------"
