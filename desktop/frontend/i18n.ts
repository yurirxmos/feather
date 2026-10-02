// User-facing strings for the webview. English is the key; Brazilian Portuguese is used when Rust
// reports a Portuguese system locale (see `src-tauri/src/i18n.rs`).

let portuguese = false;

export function setLocale(locale: string): void {
  portuguese = locale.toLowerCase().startsWith("pt");
  document.documentElement.lang = portuguese ? "pt-BR" : "en";
}

/** Translates `english` and fills `{name}` placeholders from `values`. */
export function t(english: string, values: Record<string, string | number> = {}): string {
  const text = (portuguese && PT_BR[english]) || english;
  return text.replace(/\{(\w+)\}/g, (match, name: string) => (name in values ? String(values[name]) : match));
}

export function formatDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString(portuguese ? "pt-BR" : "en-US", { year: "numeric", month: "short", day: "numeric" });
}

export const PT_BR: Record<string, string> = {
  // Panel
  "What do you want to write?": "O que você quer escrever?",
  "Refine: shorter, more formal…": "Refine: mais curto, mais formal…",
  "Generating…": "Gerando…",
  Cancel: "Cancelar",
  "Partial context": "Contexto parcial",
  "Text selected": "Texto selecionado",
  "Focused text": "Texto em foco",
  "No app context": "Sem contexto de app",
  "Reading screen…": "Lendo a tela…",
  "Capturing window…": "Capturando janela…",
  Copy: "Copiar",
  Retry: "Refazer",
  Insert: "Inserir",
  Generate: "Gerar",

  // Settings
  "Feather Settings": "Configurações do Feather",
  General: "Geral",
  Connection: "Conexão",
  "Feather Plus": "Feather Plus",
  System: "Sistema",
  "Needs attention": "Requer atenção",
  "Quit Feather": "Encerrar o Feather",
  Shortcut: "Atalho",
  "Open Feather": "Abrir o Feather",
  "Another app is using this shortcut. Choose a different one.": "Outro app está usando este atalho. Escolha outro.",
  Context: "Contexto",
  "Include a screenshot of the active window": "Incluir uma captura da janela ativa",
  "Gives the model visual context.": "Dá contexto visual ao modelo.",
  "Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.":
    "Nada é capturado até você pressionar o atalho, e o contexto é descartado quando o painel fecha.",
  Instructions: "Instruções",
  "Set writing preferences for every response, such as “Do not use emojis or em dashes.”":
    "Defina preferências de escrita para todas as respostas, como “Não use emojis nem travessões.”",
  About: "Sobre",
  Version: "Versão",
  "Check for Updates…": "Procurar Atualizações…",
  Provider: "Provedor",
  "OpenCode Go": "OpenCode Go",
  ChatGPT: "ChatGPT",
  Account: "Conta",
  "Credentials are stored in your system's secure credential storage.":
    "As credenciais ficam guardadas no armazenamento seguro de credenciais do sistema.",
  Model: "Modelo",
  "Add an API key to load the available models.": "Adicione uma chave de API para carregar os modelos disponíveis.",
  "Couldn't load the models. Check your key and connection.":
    "Não foi possível carregar os modelos. Verifique sua chave e a conexão.",
  "API key": "Chave de API",
  "Paste your key": "Cole sua chave",
  Save: "Salvar",
  "Replace…": "Substituir…",
  Refresh: "Atualizar",
  Connected: "Conectado",
  Disconnect: "Desconectar",
  "Signing in…": "Entrando…",
  "Sign in with ChatGPT": "Entrar com ChatGPT",
  "Sign-in continues in your browser.": "O login continua no seu navegador.",
  "Signed in": "Conectado",
  "Manage…": "Gerenciar…",
  "Sign in…": "Entrar…",
  "Use Feather without your own API key. Feather never stores your prompts, screen context, or replies.":
    "Use o Feather sem sua própria chave de API. O Feather nunca armazena suas instruções, o contexto da tela nem as respostas.",
  Starter: "Starter",
  Max: "Max",
  "$5/month": "US$ 5/mês",
  "$20/month": "US$ 20/mês",
  "500 requests a month, enough for everyday replies.": "500 requisições por mês, o suficiente para as respostas do dia a dia.",
  "4,000 requests a month, for writing all day.": "4.000 requisições por mês, para quem escreve o dia todo.",
  "Sign in": "Entrar",
  Email: "E-mail",
  Plan: "Plano",
  "No plan": "Sem plano",
  Replies: "Respostas",
  "Using Feather Plus": "Usando o Feather Plus",
  "Use Feather Plus": "Usar o Feather Plus",
  "Choose a plan…": "Escolher um plano…",
  "Manage subscription…": "Gerenciar assinatura…",
  "Sign out": "Sair",
  "Usage this period": "Uso neste período",
  "Resets on {date}.": "Renova em {date}.",
  Requests: "Requisições",
  "{used} of {limit}": "{used} de {limit}",
  "What Feather can do here": "O que o Feather consegue fazer aqui",
  "Read the context around your cursor": "Ler o contexto ao redor do cursor",
  "Reads the focused field, the selection, and the window's text through accessibility.":
    "Lê o campo em foco, a seleção e o texto da janela pela acessibilidade.",
  "Capture the active window": "Capturar a janela ativa",
  "Attaches a screenshot of the window you were using.": "Anexa uma captura de tela da janela que você estava usando.",
  "Paste replies": "Colar as respostas",
  "Pastes the reply into the field you were typing in.": "Cola a resposta no campo em que você estava digitando.",
  "X11 session": "Sessão X11",
  "Available": "Disponível",
  "Unavailable": "Indisponível",
  "Feather is running in a Wayland session. Wayland does not let apps read or type into other windows, so Feather generates replies and copies them for you to paste. Log in with an X11 session to read context and paste automatically.":
    "O Feather está rodando em uma sessão Wayland. O Wayland não permite que um app leia outras janelas ou digite nelas, então o Feather gera as respostas e as copia para você colar. Entre em uma sessão X11 para ler o contexto e colar automaticamente.",
  "Some apps only share their text when assistive technologies are enabled. If context is missing, turn on accessibility support in your desktop settings.":
    "Alguns apps só compartilham o texto quando as tecnologias assistivas estão ativadas. Se faltar contexto, ative o suporte de acessibilidade nas configurações do seu ambiente de trabalho.",
  "Windows needs no extra permissions. Apps that run as administrator cannot be read or pasted into unless Feather also runs as administrator.":
    "O Windows não precisa de permissões extras. Apps que rodam como administrador não podem ser lidos nem receber texto colado, a menos que o Feather também rode como administrador.",
};
