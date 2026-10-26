# 🌾 CultivaStock

## 1. Equipe – IT Girls

* **Beatriz Hubner Razera:** Desenvolvedora Front-end e UI/UX (Interface e Experiência do Usuário). Responsável principal pela entrega e comunicação do projeto.
* **Geovana Lauer Miranda:** Desenvolvedora Back-end e Integração de Banco de Dados.
* **Anna Jullya Gonçalves Pereira:** Analista de Requisitos e Qualidade (QA/Testes).
* **Jennifer Neves Santana:** Gerente de Projeto, Arquitetura de Software e Versionamento.
* **Curso:** Análise e Desenvolvimento de Sistemas (Instituto Federal de Rondônia - Campus Ariquemes).

---

## 2. Problema e Público

* **Contexto e Problema:** Profissionais da área agronômica enfrentam dificuldades em controlar de forma eficiente a data de vencimento e o estoque real de insumos armazenados, resultando em falta de produtos essenciais ou perdas financeiras por descarte de itens vencidos.
* **Público-alvo:** Agrônomos, fazendeiros, produtores rurais e gestores de plantio.

---

## 3. Solução

* **Decisões que a solução apoia:** O sistema apoia decisões estratégicas de compras de novos insumos, planejamento financeiro para safras e otimização do uso de produtos antes do vencimento, evitando desperdícios.
* **Funcionalidades:** Escaneamento de imagens de notas fiscais para entrada de dados, leitura de código de barras e QR code, cálculos automáticos de taxa de consumo, painel de monitoramento de estoque em tempo real e emissão de alertas automatizados para estoque baixo ou datas de validade próximas.

---

## 4. Como Testar

* **Execução:** Acessar o sistema através do link disponibilizado pelo GIT: [inserir link aqui]

---

## 5. Dados e Critérios

* **Campos principais:** Nome do insumo, categoria, lote, data de fabricação, data de validade, quantidade atual, unidade de medida e taxa de consumo estimada.
* **Tratamentos e Alertas:** O sistema trata as datas convertendo-as para alertas visuais automatizados (ex: amarelo para vencimento, vermelho para estoque crítico).
* **Estimativas:** O aplicativo cruza a quantidade armazenada com a taxa de consumo informada para estimar a durabilidade do estoque em dias, auxiliando no timing de reposição.

---

## 6. Demonstração

* **Vídeo e Exemplos:** [Inserir link do vídeo no YouTube/Drive demonstrando o uso aqui]
> O vídeo exemplifica o fluxo e a funcionalidade do sistema para o uso real e prático.

---

## 7. Validação

* **Testes e Resultados:** Foram realizados testes de usabilidade na interface e testes de integração no banco de dados, confirmando que a leitura de códigos e os alertas automatizados disparam conforme os critérios definidos.
* **Feedback:** Avaliações preliminares indicaram uma boa aceitação do design com tema claro (*bright theme*) e alta legibilidade dos contrastes voltados para o ambiente agrícola.
* **Limitações:** Na versão atual, o sistema requer conexão com a internet para a funcionalidade de escaneamento de notas fiscais funcionar com precisão máxima. O suporte offline para sincronização de dados será aprimorado em versões futuras.

---

## 8. Tecnologias e IA

* **Ferramentas:** Android Studio e framework Flutter (Dart) para o desenvolvimento da interface móvel.
* **Finalidades das IAs:** Foram utilizadas IAs generativas (como Gemini, Claude e Antigravity) para otimização de scripts estruturais, ideação de componentes de UI/UX, prototipação de layouts responsivos (Figma/Stitch) e auxílio na resolução de bugs de código.
* **Revisão:** Todo o código e os prompts sugeridos pelas IAs foram rigorosamente revisados, adaptados e testados manualmente pela equipe de desenvolvimento para garantir a segurança e a aderência à lógica de negócios do gerenciamento agrícola.

---

## 9. Autoria e Licença

* **Referências:** Projeto original concebido para fins acadêmicos no curso de Análise e Desenvolvimento de Sistemas.
* **Condições de uso:** O software é disponibilizado apenas permitindo o uso acadêmico e estudo de código, não sendo permitida a comercialização sem autorização prévia da equipe responsável.

---

## 10. Versão de Entrega

* **Registro da versão avaliada:** Versão 1.3.0 (Release Candidate para avaliação acadêmica).