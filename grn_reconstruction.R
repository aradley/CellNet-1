# CellNet
# (C) Patrick Cahan 2012-2014

# GRN reconstruction functions


cn_grnDoRock<-function # getRawGRN, findSpecGenes, and specGRNs
(sampTab, ### sample table
 expDat, ### properly normalized expression matrix
 zscores, ### zscores
 corrs, ### pearson correlation values
 snName, ### network name prefix
 keepCT=FALSE,
 dLevel='description1',
 dLevelGK="description2",
 zThresh=4,
 qtile=0.95,
 holmThresh=1e-4,
 sizeThresh=25)
{
  targetGenes<-rownames(expDat);
  grnall<-cn_getRawGRN(zscores, corrs, targetGenes, zThresh=zThresh, snName=snName);
  specGenes<-cn_specGenesAll(expDat, sampTab, qtile=qtile, dLevel=dLevel, dLevelGK=dLevelGK);
  
  ctGRNs<-cn_specGRNs(grnall, specGenes,keepCT=keepCT, holmThresh=holmThresh, sizeThresh=sizeThresh);
  list(grnStuff=grnall, specGenes=specGenes,ctGRNs=ctGRNs);  
}

cn_getRawGRN<-function# get raw GRN, communities from zscores, and corr
(zscores, ### zscores matrix
 corrs, #### correlation matrix
 targetGenes,#### target genes
 zThresh=4,### zscore threshold
 snName="raw" ### subnetwork prefix
 ){
 
  # make a grn table
  cat("Making GRN table...\n")
  grn<-cn_extractRegsDF(zscores, corrs, targetGenes, zThresh);
  colnames(grn)[1:2]<-c("TG", "TF");
  
  # make an iGraph object and find communities
  cat("Finding communities...\n");
  igTmp<-ig_tabToIgraph(grn, directed=FALSE, weights=TRUE);
  iCommTmp<-infomap.community(igTmp,e.weights=E(igTmp)$weight);
  
  # make gene lists of the communities and name them
  geneLists<-cn_commToNames(iCommTmp, snName);
  
  # make igraphs for each subnet
  graphLists<-cn_makeSGs(igTmp, geneLists);
  
  
  list(grnTable=grn, graph=igTmp, geneLists=geneLists, graphList=graphLists);
  ### list of grnTable, graph, community  gene lists and igraphs
}

cn_specGenesAll<-function# finds general and context dependent specifc genes
(expDat, ### expression matrix
 sampTab, ### sample table
 qtile=0.95, ### quantile
 dLevel="description1",
 dLevelGK="description2"){
  matcher<-list();
  general<-cn_findSpecGenes(expDat, sampTab, qtile=qtile, dLevel=dLevel);
  ctXs<-list()# one per germlayer
  germLayers<-unique(as.vector(sampTab[,dLevelGK]));
  for(germlayer in germLayers){
    stTmp<-sampTab[sampTab[,dLevelGK]==germlayer,];
    expTmp<-expDat[,rownames(stTmp)];
    xxx<-cn_findSpecGenes(expTmp, stTmp, qtile=qtile, dLevel=dLevel);
    cts<-names(xxx);
    for(ct in cts){
      matcher[[ct]]<-germlayer;
      # remove general ct-specific genes from this set
      cat(ct," ");
      
      a<-general[[ct]];
      b<-xxx[[ct]];
      ba<-setdiff(b, a);
      both<-union(a,b);
      cat("general: ",length(a),"\t");
      cat("context: ",length(b),"\t");
      cat("comon: ",length(both),"\t");
      cat("context only: ", length(ba), "\n");
      xxx[[ct]]<-ba;
    }
    ctXs[[germlayer]]<-xxx;
  }
  ctXs[['general']]<-general;
  list(context=ctXs, matcher=matcher);
  
    # returns a list of:
    # $matcher${cell_type}->{germ_layer}
    # $context$general${cell_type}->gene vector
    #         ${germ_layer}${cell_type}->gene vector
    
}

cn_specGRNs<-function### find subnets associated with gene lists, and break them down further
(rawGRNs, ### result of running cn_getRawGRN
 geneLists, ### result of running cn_specGenesAll
 keepCT=FALSE, # whether to only keep ct-genes as part of ct-sns, alternative (default) is to just exclude CT genes from other cell types
 holmThresh=1e-4,
 sizeThresh=25){
  
  # NB: find communities that are enriched in genes in geneLists
  # geneLists$context has each germ_layer and a general group
  # Enriched communties MAY also include genes that are associated with other CTs, either as
  # in the general or context-dependent sense. Prune these genes from these eniriched subnets.
  ct_sns<-.cn_specGRNs(rawGRNs, geneLists, holmThresh,sizeThresh);

  # for each annotation/groupName, remove genes from associated communities
  # that are also CT-genes for other CTs 
  sub_newGLs<-list();
  sub_newGRs<-list();
  
  general_GLs<-list();
  general_GRs<-list();
  
  groupNames<-names(geneLists$context$general);  
  rawSN_graphs<-rawGRNs[['graphList']];
  rawSN_geneLists<-rawGRNs[['geneLists']];
  geneListsAll<-geneLists$context;
  matcher<-geneLists$matcher;
  
  for(ct in groupNames){
    
    tmpGLs<-list();
    tmpGRs<-list();
    
    nnames<-ct_sns[[ct]];
    otherCTs<-setdiff(groupNames, ct);
    otherGenes_general<-unlist(geneListsAll$general[otherCTs]);
    gll<-matcher[[ct]];
    sameGLs<-names(which(matcher==gll));
    otherCTs<-setdiff(sameGLs, ct);
    otherGenes_context<-unlist(geneListsAll[[gll]][otherCTs]);
    otherGenes<-union(otherGenes_general, otherGenes_context);
    
    myGenes<-union(geneListsAll$general[[ct]], geneListsAll[[gll]][[ct]]);
    
    ii<-1;
    for(nname in nnames){
      newName<-paste("SN_", ct,"_",ii,sep='');
      cat(ct, " ", nname,"", length(rawSN_geneLists[[nname]]), " ... ");
      subg<-rawSN_graphs[[nname]];
      
      grnGenes<-V(subg)$name;
      
      if(!keepCT){
        # remove target genes that are considered specific to other cell types
        newGenes<-setdiff(grnGenes, otherGenes);
      }
      else{
        newGenes<-intersect(myGenes, grnGenes);
      }
      
      tmpGRs[[newName]]<-induced.subgraph(subg,newGenes);
      tmpGLs[[newName]]<-newGenes;
      ii<-ii+1;
    }
    sub_newGLs[[ct]]<-tmpGLs;
    sub_newGRs[[ct]]<-tmpGRs;
    
    # merge these
    general_GLs[[ct]]<-sort(unique(as.vector(unlist(tmpGLs))));
    general_GRs[[ct]]<-cn_graphMerge(tmpGRs);
  }
  list(subnets=list(graphs=sub_newGRs, geneLists=sub_newGLs), general=list(graphs=general_GRs, geneLists=general_GLs));
  ###list(graphs=sub_newGRs, geneLists=sub_newGLs);
  ### list of igraphs=list({ct}=list), gene_lists
}

.cn_specGRNs<-function### find and merge enriched communities
(rawGRNs, ### result of running cn_getRawGRN
 geneLists, ### result of running cn_specGenesAll
 holmThresh=1e-4,
 sizeThresh=25){
  # init
  groupNames<-names(geneLists$context$general);
  
  rawSN_geneLists<-rawGRNs[['geneLists']];
  
  allgenes<-union(rawGRNs[['grnTable']][,"TF"], rawGRNs[['grnTable']][,"TG"]);
  
  # find communities enriched in geneLists genes
  cat("Finding communities enriched for provided gene sets...\n");
  contexts<-names(geneLists$context);
  
  ct_sns<-list();
  for(context in contexts){
    ct_sns[[context]]<-sigOvers(rawSN_geneLists, geneLists$context[[context]], allgenes, holmThresh=holmThresh, sizeThresh=sizeThresh);
  }
  
  # a community can be detected as enriched in either the gneral and/or context gene lists
  # for each CT,create one list of communities enriched in either case.
  ct_sns2<-list();
  for(groupName in groupNames){
    a<-ct_sns[['general']][[groupName]];
    gll<-geneLists$matcher[[groupName]];
    b<-ct_sns[[gll]][[groupName]];
    ct_sns2[[groupName]]<-union(a,b);
  }
  ct_sns2;
}


cn_findSpecGenes<-function# find genes that are preferentially expressed in specified samples
(expDat, ### expression matrix
 sampTab, ### sample table
 qtile=0.95, ### quantile
 dLevel="description1" #### annotation level to group on
 ){
  
  cat("Template matching...\n")
  myPatternG<-cn_sampR_to_pattern(as.vector(sampTab[,dLevel]));
  specificSets<-apply(myPatternG, 1, cn_testPattern, expDat=expDat);

  # adaptively extract the best genes per lineage
  cat("First pass identification of specific gene sets...\n")
  cvalT<-vector();
  ctGenes<-list();
  ctNames<-unique(as.vector(sampTab[,dLevel]));
  for(ctName in ctNames){
    x<-specificSets[[ctName]];
    cval<-quantile(x$cval, qtile);
    tmp<-rownames(x[x$cval>cval,]);
    ctGenes[[ctName]]<-tmp;
    cvalT<-append(cvalT, cval);
  }
  
  cat("Prune common genes...\n");
  # now limit to genes exclusive to each list
  specGenes<-list();
  for(ctName in ctNames){
    others<-setdiff(ctNames, ctName);
    x<-setdiff( ctGenes[[ctName]], unlist(ctGenes[others]));
    specGenes[[ctName]]<-x;
  }
  specGenes;
}



cn_makeSGs<-function# make induced subgraphs from gene lists and iGraph object
(bigIG,### super-graph
 geneLists ### gene lists
){
  
  allGenes<-V(bigIG)$name;
  subGraphs<-list();
  nnames<-names(geneLists); 
  for(nname in nnames){
    genes<-intersect(allGenes, geneLists[[nname]]);    
    subGraphs[[nname]] <-  induced.subgraph(bigIG, genes);
  }
  subGraphs;
}


ig_tabToIgraph<-function# return a iGraph object
(grnTab, ### table of TF, TF, maybe zscores, maybe correlations
 simplify=TRUE,
 directed=FALSE,
 weights=TRUE
){
  # Note: this adds an nEnts vertex attribute to count the number of entities in the sub-net
  
  
  tmpAns<-as.matrix(grnTab[,c("TF", "TG")]);
  regs<-as.vector(unique(grnTab[,"TF"]));
  ###cat("Length TFs:", length(regs), "\n");
  targs<-setdiff( as.vector(grnTab[,"TG"]), regs);
  
###  cat("Length TGs:", length(targs), "\n");
  myRegs<-rep("Regulator", length=length(regs));
  myTargs<-rep("Target", length=length(targs));
  
  types<-c(myRegs, myTargs);
  verticies<-data.frame(name=c(regs,targs), label=c(regs,targs), type=types);
  
  iG<-graph.data.frame(tmpAns,directed=directed,v=verticies);
  
  if(weights){
    #E(iG)$weight<-grnTab$weight;    
    E(iG)$weight<-grnTab$zscore;    
  }
  
  if(simplify){
    iG<-simplify(iG);
  }
  V(iG)$nEnts<-1;
  iG;
}


cn_commToNames<-function # return a named list, wrapper to celnet_commToNames
(commObj,
 prefix
){
  ans<-list();
  comms<-communities(commObj);
  for(i in seq(length(comms))){
    nname<-paste(prefix,"_sn_",i,sep='');
    ans[[nname]]<-commObj$names[comms[[i]]];
  }
  ans;
}

cn_sampR_to_pattern<-function# return a pattern for use in cn_testPattern (template matching)
(sampR){
  d_ids<-unique(as.vector(sampR));
  nnnc<-length(sampR);
  ans<-matrix(nrow=length(d_ids), ncol=nnnc);
  for(i in seq(length(d_ids))){
    x<-rep(0,nnnc);
    x[which(sampR==d_ids[i])]<-1;
    ans[i,]<-x;
  }
  colnames(ans)<-as.vector(sampR);
  rownames(ans)<-d_ids;
  ans;
}

cn_testPattern<-function(pattern, expDat){
  pval<-vector();
  cval<-vector();
  geneids<-rownames(expDat);
  llfit<-ls.print(lsfit(pattern, t(expDat)), digits=25, print=FALSE);
  xxx<-matrix( unlist(llfit$coef), ncol=8,byrow=TRUE);
  ccorr<-xxx[,6];
  cval<- sqrt(as.numeric(llfit$summary[,2])) * sign(ccorr);
  pval<-as.numeric(xxx[,8]);
  
  #qval<-qvalue(pval)$qval;
  holm<-p.adjust(pval, method='holm');
  #data.frame(row.names=geneids, pval=pval, cval=cval, qval=qval, holm=holm);
  data.frame(row.names=geneids, pval=pval, cval=cval,holm=holm);
}


cn_extractRegsDF<-function# extracts the TRs, zscores, and corr values passing thresh
(zscores, # zscore matrix, non-TFs already removed from columns
 corrMatrix, # correlation matrix
 genes, # vector of target genes
 threshold # zscore threshold
){
  
  # note: a named list of dfs (pos, neg): target, reg, zscore, corr
  ##ans<-list();
  
  targets<-vector();
  regulators=vector();
  zscoresX<-vector();
  correlations<-vector();
  
  targets<-rep('', 1e6);
  regulators<-rep('', 1e6);
  zscoresX<-rep(0, 1e6);
  correlations<-rep(0, 1e6);
  
  str<-1;
  stp<-1;
  for(target in genes){
    x<-zscores[target,];
    regs<-names(which(x>threshold));
    if(length(regs)>0){
      zzs<-x[regs];
      corrs<-corrMatrix[target,regs];
      ncount<-length(regs);
      stp<-str+ncount-1;
      targets[str:stp]<-rep(target, ncount);
      #    targets<-append(targets,rep(target, ncount));
      regulators[str:stp]<-regs;
      #regulators<-append(regulators, regs);
      #    zscoresX<-append(zscoresX, zzs);
      zscoresX[str:stp]<-zzs;
      correlations[str:stp]<-corrs;
      str<-stp+1;
    }
    #    correlations<-append(correlations, corrs);
  }
  targets<-targets[1:stp];
  regulators<-regulators[1:stp];
  zscoresX<-zscoresX[1:stp];
  correlations<-correlations[1:stp];
  
  
  data.frame(target=targets, reg=regulators, zscore=zscoresX, corr=correlations);
}


sample_profiles_grn<-function# sample equivalent numbers of profiles per cell type
(sampTab,### sample table
  minNum=NULL, # min number of samples to get per CT
  dLevel="description1" ### grouping
  ){

  nperCT<-table(sampTab[,dLevel]);   
  if(is.null(minNum)){
    minNum<-min(nperCT);
  }

  nsamps<-vector();
  ctts<-names(nperCT);
  for(ctt in ctts){
    stTmp<-sampTab[sampTab[,dLevel]==ctt,];
    cat(ctt,":",nrow(stTmp),"\n");
    ids<-sample( rownames(stTmp),minNum);
    nsamps<-append(nsamps, ids);
  }
  sampTab[nsamps,];
}






