#!/bin/bash

echo "##################################"
echo "# observability-tools-install.sh #"
echo "##################################"

# --- Configurações ---
CLUSTER_NAME="observability-cluster"
KIND_CONFIG="./kind-config.yaml"

# Caminhos para os manifestos YAML puros
PROMETHEUS_MANIFEST="./.settings/prometheus-service.yaml" # INTEGRADO AQUI
GRAFANA_MANIFEST="./.settings/grafana-service.yaml"
OTEL_CONFIG_MANIFEST="./.settings/otel-collector-config.yaml"
OTEL_SERVICE_MANIFEST="./.settings/otel-collector-service.yaml"
OTEL_MONITOR_MANIFEST="./.settings/otel-collector-monitor.yaml"

# URLs oficiais mantidas para o OpenTelemetry (Se decidir usar o Helm do OTel futuramente)
OTEL_HELM_URL="https://github.io"
K8S_CONTEXT="kind-$CLUSTER_NAME"

echo "🏗️  Iniciando Bootstrap da Infraestrutura..."

# 0. Sincronizar o relógio do sistema (WSL2)
echo "🕒 Sincronizando relógio do sistema no WSL2..."
if grep -qi microsoft /proc/version; then
    if ! command -v ntpdate &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq ntpdate > /dev/null 2>&1
    fi
    sudo ntpdate -s ://windows.com || sudo ntpdate -s pool.ntp.org
fi

# 1. Criar Cluster se não existir
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "☸️  Cluster '$CLUSTER_NAME' já está ativo."
else
    echo "🚀 Criando cluster '$CLUSTER_NAME'..."
    kind create cluster --config "$KIND_CONFIG" || { echo "❌ Erro ao criar cluster"; exit 1; }
fi

# 🔄 Garantir o contexto correto do kubectl
kubectl config use-context "$K8S_CONTEXT"

# 2. Criar o namespace de observabilidade
echo "🔄 Criando namespace 'observability'..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# 3. Remover resíduos antigos do Helm do Prometheus para liberar RAM
echo "🧹 Limpando instalações antigas do Helm para evitar conflitos..."
helm uninstall kube-stack -n observability 2>/dev/null
kubectl delete mutatingwebhookconfigurations --all 2>/dev/null
kubectl delete validatingwebhookconfigurations --all 2>/dev/null

# 4. Instalar o Prometheus via Manifesto Puro (Ultra-Leve)
echo "📥 Aplicando manifesto puro do Prometheus (Deployment/Service)..."
if [ -f "$PROMETHEUS_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$PROMETHEUS_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $PROMETHEUS_MANIFEST"
    exit 1
fi

# 4.1 Instalar o Grafana Customizado
echo "📥 Aplicando manifesto puro do Grafana (Deployment/Service)..."
if [ -f "$GRAFANA_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$GRAFANA_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $GRAFANA_MANIFEST"
    exit 1
fi

# 5. Instalar as configurações do OpenTelemetry Collector (ConfigMap)
echo "📥 Aplicando ConfigMap do OpenTelemetry Collector..."
if [ -f "$OTEL_CONFIG_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$OTEL_CONFIG_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $OTEL_CONFIG_MANIFEST"
    exit 1
fi

# 5.1 Instalar o OpenTelemetry Collector (Service/Deployment)
echo "📥 Aplicando manifesto do OpenTelemetry Collector..."
if [ -f "$OTEL_SERVICE_MANIFEST" ]; then
    kubectl apply --insecure-skip-tls-verify=true -f "$OTEL_SERVICE_MANIFEST"
else
    echo "❌ Erro: Arquivo não encontrado em: $OTEL_SERVICE_MANIFEST"
    exit 1
fi

# 6. Aguardar a inicialização dos serviços principais
echo "⏳ Aguardando os containers baixarem (Apenas 1 réplica de cada)..."
sleep 10

echo "🕒 Verificando status do Prometheus..."
kubectl wait --insecure-skip-tls-verify=true --for=condition=ready pod -l app=prometheus -n observability --timeout=120s

echo "🕒 Verificando status do Grafana..."
kubectl wait --insecure-skip-tls-verify=true --for=condition=ready pod -l app=grafana -n observability --timeout=120s

echo "🕒 Verificando status do OpenTelemetry Collector..."
kubectl wait --insecure-skip-tls-verify=true --for=condition=ready pod -l app=otel-collector -n observability --timeout=120s

echo "--------------------------------------------------"
echo "✅ INFRAESTRUTURA E STACK PRONTAS PARA USO!"
echo "🌐 Acesse o Prometheus localmente: http://localhost:9090"
echo "🌐 Acesse o Grafana localmente: http://localhost:3000 (NodePort: 32300)"
echo "🔌 Porta OTLP gRPC Ativa: localhost:4317 (NodePort: 30317)"
echo "🔌 Porta OTLP HTTP Ativa: localhost:4318 (NodePort: 30318)"
echo "📊 Métricas Internas do OTel sendo coletadas via ServiceMonitor!"
echo "🔐 Senha Padrão do Grafana: definida no seu manifesto personalizado"
echo "--------------------------------------------------"
