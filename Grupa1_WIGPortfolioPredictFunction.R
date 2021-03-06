install.packages("lmtest")
install.packages("data.table")
install.packages("TSA")
install.packages("forecast")
install.packages("fGarch")
library(data.table)
library(TSA)
library(forecast)
library(fGarch)
library(lmtest)

## Parametr portfolio do kt�rego przypisujemy lokalizacj� i nazw� pliku z portfelem do importu do funkcji
portfolio <- "C:/Users/Grzesiek/Documents/GIT/predictions/portfolio.rds"
## Parametr ExportRdsFileName do kt�rego przypisujemy lokalizacj� i nazw� pliku ze zleceniami do eksportu
ExportRdsFileName <- "C:/Users/Grzesiek/Documents/GIT/predictions/Grupa1_Predykcja.rds"
## Parametr trainDatatrainData do kt�rego przypisujemy lokazlizacj� i nazw� pliku z danymi trenuj�cymi do importu do funkcji
trainData <- "C:/Users/Grzesiek/Documents/GIT/predictions/wig30components.RDS"

AutoPredict = function(
  trainData,
  portfolio,
  ExportRdsFileName
){  
  
  ## Pobieramy dane trenuj�ce
  readRDS(file = trainData)-> close
  
  ## Pobieramy dane portfela
  readRDS(file = portfolio)-> InvestingPortfolio
  
  
  ## Tworzymy tabele, do kt�rej wprwadzimy predykcje poszczeg�lnych instrument�w
  CompanyReturns <- data.frame(
    row.names=c(
      'acp', 'alr', 'att', 'bhw', 'bzw', 'ccc', 'cdr', 'cps', 'ena', 'eng',
      'eur', 'gtc', 'ing', 'jsw', 'ker', 'kgh', 'lpp', 'lts', 'lwb', 'mbk',
      'opl', 'peo', 'pge', 'pgn', 'pkn', 'pko', 'pkp', 'pzu', 'sns', 'tpe'
    ),
    quantity=c( rep(0, 30))
  )
  
  
  ## Oczyszczamy dane z brakuj�cych warto�ci ("NA") oraz dzi�ki temu ograniczamy zakres danych do tego samego zakresu datowego
  ## Dzieki temu, mo�emy ograniczy� zjawiska sezonowo�ci szereg�w oraz pozbywamy si� warto�ci
  ## Nie klasyfikuj�cych si� do przeprowadzenia analizy - dane takie mog� zak��ca� szeregi czasowe
  ## Usuneli�my tak�e luki czasowe, kt�re nie maj� wp�ywu na pozytywne przeprowadzenie analizy.

  ncol(close) -> ColumnCounts
  
  for(i in 1:ColumnCounts) {
    close[!is.na(close[,i]),]->close
  }
  
  ## W tej cz�ci dokonujemy predykcji poszczeg�lnych sp�ek
  for(i in 1:ColumnCounts){
    
    ## Pobranie danych oraz stworzenie do nich st�p zwrotu w celu p�niejszej analizy
    
    close[,i] -> DataSet
    
    
    length(DataSet) -> T
    log(DataSet[-1] / DataSet[-T]) -> ReturnDataSet
    
    
    ## Automatycznie dobierany model trendu do danych oraz predykcja za pomoca funkcji predict
    
    etsModel <- ets( DataSet, model="ZZZ")
    
    predict(etsModel, n.ahead=1)$mean[1] -> EtsPredictValue
    
    ##Logarytmiczna stopa zwrotu po zastosowaniu autodopasowanego modelu trendu
    log(EtsPredictValue/DataSet[T] ) -> estPredictReturnValue
    
    ## ARIMA MODEL - Prediction - u�ylismy tutaj funkcji auto.arima, kt�ra automatycznie dopasowuje
    ## parametry p,d,q w modelu zgodnie z dopasowaniem parametr�w do kryteri�w informacyjnych AIC i BIC
    ## Co prawda nie u�ywali�my jej na zaj�ciach. Zosta�a ona tutaj wykorzystana, aby zwi�kszy� wydajno�� skryptu
    ## oraz poprawno�� dopasowania parametr�w do modelu.
    ## U�ywamy testu KPSS oraz adf do weryfikacji stacjonarno�ci szeregu (Jednego z g��wnych za�o�e� testu arima)
    
    adf.test(ReturnDataSet) -> adfTestResults
    kpss.test(ReturnDataSet) -> kpssTestResults
    
    if ( adfTestResults$p.value <= 0.01 && kpssTestResults$p.value > 0.01){    
      
      auto.arima(ReturnDataSet) -> ArimaModel
      
      
      forecast( ArimaModel, h=1, fan=TRUE)-> ArmiaForecast
      ArmiaForecast$mean[1] -> ArimaForecastValue
      
    }
    
    ##GARCH Model
    
    garchFit(~garch(1,1), ReturnDataSet, cond.dist='sstd', trace=FALSE) -> GarchModel
    predict(GarchModel, n.ahead=1)[,1] -> GarchPredictValue
    
    if(!is.null(ArimaForecastValue)){
      
      (GarchPredictValue + ArimaForecastValue + estPredictReturnValue )/3 -> ReturnValue
    } 
    if  (is.null(ArimaForecastValue)){
      (GarchPredictValue + estPredictReturnValue )/2  -> ReturnValue
    }
    
    CompanyReturns[i,1] <- ReturnValue
    
    NULL -> ReturnValue
    NULL -> ArimaForecastValue
    NULL -> GarchPredictValue
    NULL -> estPredictReturnValue
  }
  
  ## Sprzeda� i kupno inwestycji
  
  SummariseTransactions <- data.frame(
    row.names=c(
      'acp', 'alr', 'att', 'bhw', 'bzw', 'ccc', 'cdr', 'cps', 'ena', 'eng',
      'eur', 'gtc', 'ing', 'jsw', 'ker', 'kgh', 'lpp', 'lts', 'lwb', 'mbk',
      'opl', 'peo', 'pge', 'pgn', 'pkn', 'pko', 'pkp', 'pzu', 'sns', 'tpe'
    ),
    quantity=c(rep(0, 30)),
    value=c(rep(0, 30))
  )
  
  nrow(SummariseTransactions) -> SummarisingRows
  nrow(close) -> CloseRows
  
  ## Przypisujemy poszczeg�lnym instrumentom aktualne ceny instrument�w  
  
  for(i in 1:SummarisingRows){
    
    SummariseTransactions[i,2] <- close[CloseRows,i] 
    
  }
  
  ## Sprzeda� nierentownych sp�ek - sprzedajemy, je�eli ich prognozowana stopa zwrotu jest mniejsza lub r�wna 0

  InvestingCash <- InvestingPortfolio[1,2] 
  CountPlusReturns <- 0 ## liczba dodatnich predykcji - liczba ju� zainwestowanych dodatnich predykcji
  
  for (i in 1:SummarisingRows){
    if(CompanyReturns[i,1]<= 0 ){
      
      SummariseTransactions[i,1] <- -InvestingPortfolio[i+1,1]
      InvestingCash <- InvestingCash - SummariseTransactions[i,1]*SummariseTransactions[i,2]
      
    }
    
    if (CompanyReturns[i,1] > 0 && InvestingPortfolio[i+1,1] <= 0 ){
      
      CountPlusReturns <- CountPlusReturns + 1
      
    }
  }
  
  ## Nasz wewn�trzny wska�nik inwestycyjny okre�laj�cy pu�ap kwoty inwestycyjnej w dany instrument.
  ## Dzielimy nasz kapita� inwestycyjny na cze�ci, kt�re mo�emy zainwestowa� w konkretne sp�ki w stosunku 1:1
  ## NIe potrafili�my inaczej tego zrobi�
  
  InvestingCash / CountPlusReturns -> InvestingAmountIndex
  
  for (i in 1:SummarisingRows){
    
    if (CompanyReturns[i,1] > 0 && InvestingPortfolio[i+1,1] <= 0 ){
      
      SummariseTransactions[i,1] <- floor((InvestingAmountIndex/SummariseTransactions[i,2]))
      
    }
  }
  
  #usuwanie warto�ci 0 z tabeli zaawieraj�cej transakcje
  SummariseTransactions<-SummariseTransactions[!(SummariseTransactions$quantity==0),]
  saveRDS(SummariseTransactions, file = ExportRdsFileName)
  
  return(SummariseTransactions)
  
}


AutoPredict(trainData,portfolio,ExportRdsFileName)  

  