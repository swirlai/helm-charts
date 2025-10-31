#### Common

{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Create chart name and version as used by the chart label. */}}
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

#### Docker Secrets
{{/*
Render imagePullSecrets block
Usage: {{ include "swirl.imagePullSecrets" (dict "context" .) }}
*/}}
{{- define "swirl.imagePullSecrets" }}
{{- $context := .context -}}
{{- $secrets := $context.Values.imagePullSecrets -}}
{{- if and $context.Values.defaultDockerRegistry.username $context.Values.defaultDockerRegistry.password -}}
   {{- $secrets = append $secrets "docker-secret" -}}
{{- end -}}
{{- if gt (len $secrets) 0 }}
{{ printf "imagePullSecrets:" | indent 6 }}
{{- range $secrets }}
{{ printf "- name: %s"  . | indent 8 }}
{{- end }}
{{- end }}
{{- end }}

#### Swirl

{{/* Deployment name. */}}
{{- define "swirl.name" -}}
{{- default "swirl" .Values.swirl.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels */}}
{{- define "swirl.selectorLabels" -}}
app.kubernetes.io/name: {{ include "swirl.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Create the name of the service account to use */}}
{{- define "swirl.serviceAccountName" -}}
{{- if .Values.swirl.serviceAccount.create }}
{{- default (include "swirl.name" .) .Values.swirl.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.swirl.serviceAccount.name }}
{{- end }}
{{- end }}
