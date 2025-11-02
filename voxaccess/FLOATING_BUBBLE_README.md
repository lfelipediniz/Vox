# Floating Bubble - Assistente IA

## 📱 Funcionalidades Implementadas

### 1. **Bubble Flutuante com Ícone de IA**
- Ícone: `psychology` (cérebro/IA)
- Cor azul gradiente
- Visível mesmo quando o app é minimizado
- Tamanho: 60x60 pixels

### 2. **Menu Flutuante**
- Aparece acima do bubble quando clicado
- Contém 2 botões:
  - **Botão 1** (Microfone): Para comandos de voz
  - **Botão 2** (Texto): Para comandos textuais
- Design com sombra e bordas arredondadas

### 3. **Funcionalidade de Arrastar**
- O bubble pode ser arrastado para qualquer posição da tela
- Funciona através de `GestureDetector` com `onPanUpdate`
- Mantém a posição escolhida pelo usuário

### 4. **Sistema de Permissões**
- Solicita permissão `SYSTEM_ALERT_WINDOW` (overlay)
- Botão no app principal para verificar/solicitar permissões
- Redireciona para configurações do sistema se necessário

### 5. **Controle pelo App Principal**
- Interface limpa e intuitiva
- Indicador visual de status (ativo/inativo)
- Botões para ativar/desativar o bubble
- Instruções de uso
- Feedback de ações realizadas

## 🔧 Arquivos Modificados/Criados

### Novos Arquivos:
- `lib/floating_bubble_overlay.dart` - Widget do bubble flutuante

### Arquivos Modificados:
- `lib/main.dart` - App principal com controle do overlay
- `pubspec.yaml` - Dependências adicionadas
- `android/app/src/main/AndroidManifest.xml` - Permissões e serviço

## 📦 Dependências Adicionadas

```yaml
flutter_overlay_window: ^0.5.0  # Para criar overlay flutuante
permission_handler: ^11.0.0     # Para gerenciar permissões
```

## 🔐 Permissões Necessárias (Android)

```xml
- SYSTEM_ALERT_WINDOW        # Desenhar sobre outros apps
- FOREGROUND_SERVICE         # Serviço em foreground
- FOREGROUND_SERVICE_SPECIAL_USE  # Uso especial do serviço
- WAKE_LOCK                  # Manter dispositivo acordado
```

## 🎨 Características Visuais

### Bubble:
- Formato circular
- Gradiente azul
- Sombra com blur
- Ícone de cérebro (IA) centralizado

### Menu:
- Fundo branco
- Bordas arredondadas (15px)
- Dois botões com ícones coloridos
- Separador entre botões
- Animação de abertura/fechamento

### Interações:
- **Tap no bubble**: Abre/fecha menu
- **Arrastar**: Move o bubble
- **Tap nos botões do menu**: Executa ação e muda cor do bubble

## 📱 Como Usar

1. **Abrir o app VoxAccess**
2. **Clicar em "Ativar Bubble"**
3. **Conceder permissão** se solicitado
4. **O bubble aparecerá** na tela
5. **Arrastar** para posicionar onde desejar
6. **Clicar no bubble** para abrir menu
7. **Selecionar** uma das opções do menu
8. **Minimizar o app** - o bubble continuará visível!

## 🔄 Estados do Bubble

- **Azul**: Estado padrão
- **Verde**: Após clicar no botão de microfone
- **Roxo**: Após clicar no botão de texto

## 🛠️ Próximas Melhorias Possíveis

- [ ] Integração com API de IA para processamento real
- [ ] Reconhecimento de voz funcional
- [ ] Histórico de comandos
- [ ] Customização de cores e tamanho
- [ ] Mais opções no menu flutuante
- [ ] Notificações de status
- [ ] Salvar posição preferida do bubble

## ⚠️ Observações Importantes

- Funciona apenas no **Android** (overlay não disponível no iOS por restrições do sistema)
- Requer **Android 6.0+** para funcionalidade completa
- Em alguns dispositivos, pode ser necessário habilitar manualmente a permissão nas configurações
- O bubble permanece visível até ser desativado pelo usuário ou o app ser fechado completamente

## 🐛 Troubleshooting

### Bubble não aparece?
- Verifique se a permissão foi concedida
- Vá em Configurações > Apps > VoxAccess > Permissões
- Habilite "Exibir sobre outros apps"

### App não compila?
- Execute: `flutter clean && flutter pub get`
- Verifique se tem internet para baixar dependências

### Menu não abre?
- Certifique-se de tocar (não arrastar) no bubble
- Aguarde a animação completar
