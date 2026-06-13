#!/bin/bash

echo "##################################"
echo "# bootstrap.sh                   #"
echo "##################################"

# --- Configurações ---
CLUSTER_NAME="observability-cluster"
KIND_CONFIG="./kind-config.yaml"

# O Kind gera o nome do contexto juntando "kind-" com o nome do cluster
K8S_CONTEXT="kind-$CLUSTER_NAME"

echo "🏗️  Iniciando Bootstrap da Infraestrutura..."

# 1. Criar Cluster se não existir
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "☸️  Cluster '$CLUSTER_NAME' já está ativo."
else
    echo "🚀 Criando cluster '$CLUSTER_NAME' do zero..."
    kind create cluster --config "$KIND_CONFIG" || { echo "❌ Erro ao criar cluster"; exit 1; }
fi

# 🔄 Garantir o contexto correto do kubectl
echo "🔄 Alternando contexto do kubectl para '$K8S_CONTEXT'..."
kubectl config use-context "$K8S_CONTEXT" || { echo "❌ Erro ao mudar de contexto"; exit 1; }

echo "✅ BOOTSTRAP CONCLUÍDO!"
echo "--------------------------------------------------"
echo "🌐 Cluster de Observabilidade: $CLUSTER_NAME"
echo "🔌 Porta OTLP/gRPC Configurada: localhost:4317"
echo "✅ Pronto para receber os manifestos de observabilidade manualmente."
echo "--------------------------------------------------"
